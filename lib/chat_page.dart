import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import 'app_settings.dart';
import 'chat_backend.dart';
import 'full_image_page.dart';
import 'security/encryption_service.dart';
import 'supabase_media_service.dart';
import 'user_profile_page.dart';

class ChatPage extends StatefulWidget {
  final String userName;
  final String userId;

  const ChatPage({
    super.key,
    required this.userName,
    required this.userId,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final TextEditingController msgController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final currentUser = FirebaseAuth.instance.currentUser;
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _cleaning = false;
  Timer? _typingTimer;
  Timer? _recordTimer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _unseenSub;

  static const primaryRed = Color(0xFFE63946);

  String myAlgo = 'AES';
  String myKey = '';
  String theirAlgo = 'AES';
  String theirKey = '';
  bool keysLoaded = false;
  String _sharedKey = '';
  late final String _chatFallbackKey;
  bool _isRecording = false;
  int _recordSeconds = 0;
  String? _playingMessageId;
  String? _recordedVoicePath;
  int? _recordedVoiceDurationMs;
  bool _sendingRecordedVoice = false;
  Map<String, dynamic>? _replyingTo;
  bool _isBlocked = false;

  String get chatId {
    List ids = [currentUser!.uid, widget.userId];
    ids.sort();
    return ids.join("_");
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chatFallbackKey = _buildFallbackChatKey();
    _ensureChatReady();
    _loadKeys();
    _markMessagesAsSeen();
    _listenForUnreadMessages();
    _cleanupExpiredMessages();
    _loadBlockState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    msgController.dispose();
    scrollController.dispose();
    _audioPlayer.dispose();
    _typingTimer?.cancel();
    _unseenSub?.cancel();
    _recorder.dispose();
    ChatBackend.setTyping(widget.userId, false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _markMessagesAsSeen();
    }
  }

  Future<void> _loadBlockState() async {
    final blocked = await ChatBackend.isBlockedEitherWay(widget.userId);
    if (mounted) {
      setState(() {
        _isBlocked = blocked;
      });
    }
  }

  Future<void> _ensureChatReady() async {
    try {
      await ChatBackend.ensureAcceptedChat(widget.userId);
    } catch (_) {
      // Ignore here; send action will still show error if needed.
    }
  }

  // ✅ Mark all unread messages as seen
  Future<void> _markMessagesAsSeen() async {
    try {
      final messages = await FirebaseFirestore.instance
          .collection("chats")
          .doc(chatId)
          .collection("messages")
          .where("seen", isEqualTo: false)
          .where("receiverId", isEqualTo: currentUser!.uid)
          .get();

      for (var doc in messages.docs) {
        await doc.reference.update({"seen": true});
      }
    } catch (e) {
      debugPrint("Mark seen error: $e");
    }
  }

  void _listenForUnreadMessages() {
    _unseenSub?.cancel();
    _unseenSub = FirebaseFirestore.instance
        .collection("chats")
        .doc(chatId)
        .collection("messages")
        .where("seen", isEqualTo: false)
        .where("receiverId", isEqualTo: currentUser!.uid)
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.docs.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {"seen": true});
      }
      await batch.commit();
    });
  }

  String _buildFallbackChatKey() {
    final digest = base64Url.encode(utf8.encode(chatId));
    return digest.padRight(44, 'A').substring(0, 44);
  }

  String _safeAlgo(String algo) {
    final a = algo.trim();
    if (a == 'ChaCha20') return 'ChaCha20';
    if (a.toUpperCase() == 'RSA') return 'RSA';
    if (a.toUpperCase() == 'AESGCM' || a.toUpperCase() == 'AES-GCM') {
      return 'AESGCM';
    }
    return 'AES';
  }

  String _safeKey(Map<String, dynamic> data, String algo) {
    String key = data['encryptionKey'] ?? '';
    if (key.isEmpty) key = EncryptionService.generateAESKey();
    return key;
  }

  Future<void> _loadKeys() async {
    try {
      final myDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser!.uid)
          .get();

      final theirDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();

      if (!myDoc.exists || !theirDoc.exists) {
        _fallbackToAES();
        return;
      }

      final myData = myDoc.data() as Map<String, dynamic>;
      final theirData = theirDoc.data() as Map<String, dynamic>;

      // ✅ Prefer ECDH-derived shared key if both users have keys
      String sharedKey = '';
      final myEcdhPriv = (myData['ecdhPrivateKey'] ?? '') as String;
      final theirEcdhPub = (theirData['ecdhPublicKey'] ?? '') as String;
      if (myEcdhPriv.isNotEmpty && theirEcdhPub.isNotEmpty) {
        try {
          sharedKey = EncryptionService.deriveSharedKeyEcdhP256(
            myPrivateKeyBase64Url: myEcdhPriv,
            theirPublicKeyBase64Url: theirEcdhPub,
          );
        } catch (_) {
          sharedKey = '';
        }
      }

      setState(() {
        _sharedKey = sharedKey;
        if (_sharedKey.isNotEmpty) {
          // With ECDH, both sides derive the same symmetric key
          myAlgo = 'AESGCM';
          theirAlgo = 'AESGCM';
          myKey = _sharedKey;
          theirKey = _sharedKey;
        } else {
          myAlgo = _safeAlgo(myData['algorithm'] ?? 'AES');
          theirAlgo = _safeAlgo(theirData['algorithm'] ?? 'AES');
          myKey = _safeKey(myData, myAlgo);
          theirKey = _safeKey(theirData, theirAlgo);
        }
        keysLoaded = true;
      });

      debugPrint("✅ Keys loaded — Me: $myAlgo | Them: $theirAlgo");
    } catch (e) {
      debugPrint("Key load error: $e");
      _fallbackToAES();
    }
  }

  void _fallbackToAES() {
    final fallbackKey = EncryptionService.generateAESKey();
    setState(() {
      myAlgo = 'AES';
      theirAlgo = 'AES';
      myKey = fallbackKey;
      theirKey = fallbackKey;
      keysLoaded = true;
    });
  }

  Future<void> _cleanupExpiredMessages() async {
    if (_cleaning) return;
    _cleaning = true;
    try {
      final now = Timestamp.now();
      final q = await FirebaseFirestore.instance
          .collection("chats")
          .doc(chatId)
          .collection("messages")
          .where("expiresAt", isLessThanOrEqualTo: now)
          .get();

      for (final d in q.docs) {
        await d.reference.delete();
      }
    } catch (_) {
      // ignore
    } finally {
      _cleaning = false;
    }
  }

  Timestamp? _computeExpiresAt() {
    if (!AppSettings.selfDestructEnabled.value) return null;
    final s = AppSettings.selfDestructSeconds.value;
    if (s <= 0) return null;
    return Timestamp.fromDate(DateTime.now().add(Duration(seconds: s)));
  }

  Future<void> sendMessage() async {
    if (msgController.text.trim().isEmpty || !keysLoaded) return;

    // Double-check block state each send so new blocks are respected immediately.
    if (await ChatBackend.isBlockedEitherWay(widget.userId)) {
      if (mounted) {
        setState(() {
          _isBlocked = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Messaging is blocked for this contact"),
          ),
        );
      }
      return;
    }

    final plainText = msgController.text.trim();
    msgController.clear();
    _onTypingChanged('');
    await _sendTextMessage(plainText);
  }

  Future<void> _sendTextMessage(String plainText) async {
    if (!keysLoaded || _isBlocked) return;

    try {
      await ChatBackend.ensureAcceptedChat(widget.userId);

      String senderAlgo = myAlgo;
      String receiverAlgo = theirAlgo;
      String encryptedForMe;
      String encryptedForThem;
      try {
        final myAlgoEnum = EncryptionService.algorithmFromString(myAlgo);
        encryptedForMe = EncryptionService.encrypt(
          plainText,
          myKey,
          myAlgoEnum,
        );

        final theirAlgoEnum = EncryptionService.algorithmFromString(theirAlgo);
        encryptedForThem = EncryptionService.encrypt(
          plainText,
          theirKey,
          theirAlgoEnum,
        );
      } catch (_) {
        senderAlgo = 'AES';
        receiverAlgo = 'AES';
        encryptedForMe = EncryptionService.encrypt(
          plainText,
          _chatFallbackKey,
          EncryptionAlgorithm.AES,
        );
        encryptedForThem = EncryptionService.encrypt(
          plainText,
          _chatFallbackKey,
          EncryptionAlgorithm.AES,
        );
      }

      final expiresAt = _computeExpiresAt();

      await FirebaseFirestore.instance
          .collection("chats")
          .doc(chatId)
          .collection("messages")
          .add({
        "type": "text",
        "encryptedForSender": encryptedForMe,
        "encryptedForReceiver": encryptedForThem,
        "senderAlgo": senderAlgo,
        "receiverAlgo": receiverAlgo,
        "senderId": currentUser!.uid,
        "receiverId": widget.userId,
        "timestamp": FieldValue.serverTimestamp(),
        "seen": false,        // ✅ read receipt
        "delivered": true,    // ✅ delivered
        "isDeleted": false,
        "deletedFor": <String>[],
        if (_replyingTo != null) "replyTo": _replyingTo,
        if (expiresAt != null) "expiresAt": expiresAt,
      });

      await FirebaseFirestore.instance
          .collection("chats")
          .doc(chatId)
          .set({
        "lastMessage": "🔐 Encrypted message",
        "lastMessageTime": FieldValue.serverTimestamp(),
        "participants": [currentUser!.uid, widget.userId],
      }, SetOptions(merge: true));
      if (mounted) {
        setState(() {
          _replyingTo = null;
        });
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Send error: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteForMe(DocumentReference ref) async {
    await ref.update({
      "deletedFor": FieldValue.arrayUnion([currentUser!.uid]),
    });
  }

  Future<void> _deleteForEveryone(DocumentReference ref) async {
    await ref.update({
      "isDeleted": true,
      "type": "text",
      "encryptedForSender": "",
      "encryptedForReceiver": "",
    });
  }

  void _showMessageActions({
    required bool isMe,
    required DocumentReference ref,
  }) {
    // Delete actions are disabled by design in this build.
  }

  String decryptMessage(Map<String, dynamic> data) {
    if ((data['type'] ?? 'text') != 'text') {
      return '';
    }
    try {
      final senderId = data['senderId'] ?? '';
      final isMe = senderId == currentUser!.uid;
      final algoText = isMe
          ? (data['senderAlgo'] ?? myAlgo).toString()
          : (data['receiverAlgo'] ?? theirAlgo).toString();
      final algo = EncryptionService.algorithmFromString(algoText);
      final cipherText = isMe
          ? (data['encryptedForSender'] ?? '').toString()
          : (data['encryptedForReceiver'] ?? '').toString();

      final decrypted = EncryptionService.decrypt(cipherText, myKey, algo);
      if (!decrypted.startsWith('[Decryption')) {
        return decrypted;
      }
      return EncryptionService.decrypt(
        cipherText,
        _chatFallbackKey,
        EncryptionAlgorithm.AES,
      );
    } catch (e) {
      return "[Decryption Error]";
    }
  }

  // ✅ Read receipt widget
  Widget _buildReadReceipt(Map<String, dynamic> data) {
    final bool seen = data['seen'] ?? false;
    final bool delivered = data['delivered'] ?? false;

    if (seen) {
      // ✅✅ Blue double tick - read
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.done_all, size: 14, color: Colors.blue),
        ],
      );
    } else if (delivered) {
      // ✅✅ Grey double tick - delivered
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.done_all, size: 14, color: Colors.white54),
        ],
      );
    } else {
      // ✅ Single tick - sent
      return const Icon(Icons.done, size: 14, color: Colors.white54);
    }
  }

  String formatTime(Timestamp? timestamp) {
    if (timestamp == null) return "";
    return DateFormat('h:mm a').format(timestamp.toDate());
  }

  Future<void> _sendMediaMessage({
    required String type,
    required Uint8List bytes,
    required String fileName,
    Map<String, dynamic>? extra,
  }) async {
    try {
      // Re-check block state before sending any media.
      if (await ChatBackend.isBlockedEitherWay(widget.userId)) {
        if (mounted) {
          setState(() {
            _isBlocked = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Messaging is blocked for this contact"),
            ),
          );
        }
        return;
      }

      await ChatBackend.ensureAcceptedChat(widget.userId);

      final expiresAt = _computeExpiresAt();
      final uploaded = await SupabaseMediaService.uploadMedia(
        chatId: chatId,
        type: type,
        fileName: fileName,
        bytes: bytes,
      );
      final url = uploaded['mediaUrl'] ?? '';
      final storagePath = uploaded['storagePath'] ?? '';

      await FirebaseFirestore.instance
          .collection("chats")
          .doc(chatId)
          .collection("messages")
          .add({
        "type": type,
        "mediaUrl": url,
        "storagePath": storagePath,
        "fileName": fileName,
        "senderId": currentUser!.uid,
        "receiverId": widget.userId,
        "timestamp": FieldValue.serverTimestamp(),
        "seen": false,
        "delivered": true,
        "isDeleted": false,
        "deletedFor": <String>[],
        if (_replyingTo != null) "replyTo": _replyingTo,
        if (expiresAt != null) "expiresAt": expiresAt,
        if (extra != null) ...extra,
      });

      await FirebaseFirestore.instance
          .collection("chats")
          .doc(chatId)
          .set({
        "lastMessage": type == "image"
            ? "📷 Photo"
            : type == "video"
                ? "🎥 Video"
                : "🎤 Voice message",
        "lastMessageTime": FieldValue.serverTimestamp(),
        "participants": [currentUser!.uid, widget.userId],
      }, SetOptions(merge: true));
      if (mounted) {
        setState(() {
          _replyingTo = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to send $type: $e")),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    final picked = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
            ],
          ),
        );
      },
    ).then((source) async {
      if (source == null) return null;
      return _picker.pickImage(source: source, imageQuality: 70);
    });
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final fileName = picked.name;
    await _sendMediaMessage(
      type: "image",
      bytes: bytes,
      fileName: fileName,
    );
  }

  Future<void> _pickVideo() async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    final fileBytes = await picked.readAsBytes();

    // Enforce simple size limit (approx) 10MB
    const maxBytes = 10 * 1024 * 1024;
    if (fileBytes.length > maxBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Video too large. Max 10MB."),
          ),
        );
      }
      return;
    }

    final fileName = picked.name;
    await _sendMediaMessage(
      type: "video",
      bytes: fileBytes,
      fileName: fileName,
    );
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _recorder.stop();
      setState(() {
        _isRecording = false;
        _recordTimer?.cancel();
      });
      _recordTimer = null;

      if (path == null) return;
      final durationMs = await _audioPlayer.setFilePath(path).then((_) {
        return _audioPlayer.duration?.inMilliseconds ?? 0;
      });
      await _audioPlayer.stop();
      if (mounted) {
        setState(() {
          _recordedVoicePath = path;
          _recordedVoiceDurationMs = durationMs;
        });
      }
    } else {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Microphone permission is required"),
            ),
          );
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
      });
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _recordSeconds += 1;
        });
      });
    }
  }

  Future<void> _sendRecordedVoice() async {
    if (_sendingRecordedVoice) return;
    final path = _recordedVoicePath;
    if (path == null) return;
    final durationMs = _recordedVoiceDurationMs ?? 0;

    setState(() {
      _sendingRecordedVoice = true;
      // Clear the "ready" UI immediately to prevent double-tap re-sends.
      _recordedVoicePath = null;
      _recordedVoiceDurationMs = null;
    });

    try {
      final file = File(path);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Recorded file no longer exists")),
          );
        }
        return;
      }

      final bytes = await file.readAsBytes();
      final fileName = path.split(Platform.pathSeparator).last;
      await _sendMediaMessage(
        type: "voice",
        bytes: bytes,
        fileName: fileName,
        extra: {"durationMs": durationMs},
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to send voice: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _sendingRecordedVoice = false;
        });
      }
    }
  }

  Future<void> _discardRecordedVoice() async {
    final path = _recordedVoicePath;
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // ignore cleanup failure
      }
    }
    if (mounted) {
      setState(() {
        _recordedVoicePath = null;
        _recordedVoiceDurationMs = null;
      });
    }
  }

  String _formatRecordTime() {
    final minutes = _recordSeconds ~/ 60;
    final seconds = _recordSeconds % 60;
    final mm = minutes.toString().padLeft(1, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return "$mm:$ss";
  }

  Future<void> _cancelRecording() async {
    if (_isRecording) {
      try {
        await _recorder.stop();
      } catch (_) {
        // ignore
      }
    }
    _recordTimer?.cancel();
    _recordTimer = null;
    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordSeconds = 0;
      });
    }
  }

  Future<void> _playVoiceMessage(
    String url,
    String messageId, {
    String? storagePath,
  }) async {
    try {
      await _audioPlayer.setUrl(url);
      setState(() {
        _playingMessageId = messageId;
      });
      await _audioPlayer.play();
      setState(() {
        _playingMessageId = null;
      });
    } catch (_) {
      // Signed URLs can expire; try refreshing once from storagePath.
      if (storagePath != null && storagePath.isNotEmpty) {
        try {
          final refreshed = await SupabaseMediaService.refreshSignedUrl(
            storagePath,
          );
          await FirebaseFirestore.instance
              .collection("chats")
              .doc(chatId)
              .collection("messages")
              .doc(messageId)
              .set({"mediaUrl": refreshed}, SetOptions(merge: true));
          await _audioPlayer.setUrl(refreshed);
          if (mounted) {
            setState(() {
              _playingMessageId = messageId;
            });
          }
          await _audioPlayer.play();
          if (mounted) {
            setState(() {
              _playingMessageId = null;
            });
          }
          return;
        } catch (_) {
          // fallthrough to user-visible error
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Unable to play audio")),
        );
      }
    }
  }

  void _setReply(Map<String, dynamic> data) {
    final preview = data['type'] == 'text'
        ? decryptMessage(data)
        : data['type'] == 'image'
            ? 'Photo'
            : data['type'] == 'video'
                ? 'Video'
                : 'Voice message';
    setState(() {
      _replyingTo = {
        'messageId': data['messageId'],
        'senderId': data['senderId'],
        'type': data['type'],
        'preview': preview,
      };
    });
  }

  void _onTypingChanged(String value) {
    if (_isBlocked) return;
    ChatBackend.setTyping(widget.userId, value.trim().isNotEmpty);
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      ChatBackend.setTyping(widget.userId, false);
    });
  }

  Widget _buildReplyPreview(
    Map<String, dynamic> replyTo,
    bool isMe,
    Color onSurface,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: (isMe ? Colors.white : onSurface).withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            replyTo['senderId'] == currentUser!.uid ? 'You' : widget.userName,
            style: TextStyle(
              color: isMe ? Colors.white : onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            replyTo['preview'] ?? '',
            style: TextStyle(
              color: (isMe ? Colors.white : onSurface).withOpacity(0.85),
              fontSize: 12,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ✅ Format last seen
  String _formatLastSeen(Timestamp? timestamp) {
    if (timestamp == null) return "last seen recently";
    final dt = timestamp.toDate();
    final now = DateTime.now();
    if (dt.day == now.day) {
      return "last seen at ${DateFormat('h:mm a').format(dt)}";
    }
    return "last seen ${DateFormat('dd/MM').format(dt)}";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cardColor = theme.cardColor;
    final onSurface = scheme.onSurface;
    final subText = onSurface.withOpacity(0.7);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: StreamBuilder<DocumentSnapshot>(
          // ✅ Real-time online status
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(widget.userId)
              .snapshots(),
          builder: (context, snapshot) {
            bool isOnline = false;
            String lastSeenText = "last seen recently";
            bool isTyping = false;

            if (snapshot.hasData && snapshot.data!.exists) {
              final data = snapshot.data!.data() as Map<String, dynamic>;
              isOnline = data['isOnline'] ?? false;
              lastSeenText = _formatLastSeen(
                  data['lastSeen'] as Timestamp?);
            }

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: ChatBackend.chatDoc(widget.userId).snapshots(),
              builder: (context, chatSnapshot) {
                if (chatSnapshot.hasData) {
                  final typing = Map<String, dynamic>.from(
                    chatSnapshot.data!.data()?['typing'] ?? const {},
                  );
                  isTyping = typing[widget.userId] == true;
                }
                return GestureDetector(
                  onTap: _isBlocked
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => UserProfilePage(userId: widget.userId),
                            ),
                          );
                        },
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            backgroundColor: scheme.primary,
                            radius: 18,
                            child: Text(
                              widget.userName[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (isOnline)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: cardColor,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.userName,
                            style: TextStyle(
                              color: onSurface,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _isBlocked
                                ? "Blocked"
                                : isTyping
                                    ? "typing..."
                                    : isOnline
                                        ? "Online"
                                        : lastSeenText,
                            style: TextStyle(
                              color: _isBlocked
                                  ? Colors.redAccent
                                  : isTyping
                                      ? scheme.primary
                                      : isOnline
                                          ? Colors.green
                                          : subText,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.lock, color: Colors.green, size: 20),
          ),
        ],
      ),

      body: !keysLoaded
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: scheme.primary),
                  SizedBox(height: 16),
                  Text(
                    "Setting up secure channel...",
                    style: TextStyle(color: subText),
                  ),
                ],
              ),
            )
          : Column(
              children: [

                // ✅ Encryption banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      vertical: 6, horizontal: 12),
                  color: Colors.green.withOpacity(0.1),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock, color: Colors.green, size: 14),
                      SizedBox(width: 6),
                      Text(
                        "Messages are end-to-end encrypted",
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                // ✅ Messages list
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection("chats")
                        .doc(chatId)
                        .collection("messages")
                        .orderBy("timestamp", descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                              ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(
                              color: primaryRed),
                        );
                      }

                      if (!snapshot.hasData ||
                          snapshot.data!.docs.isEmpty) {
                        return Center(
                          child: Text(
                            "No messages yet.\nSay Hello! 👋",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: subText),
                          ),
                        );
                      }

                      final messages = snapshot.data!.docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final deletedFor =
                            List<String>.from(data['deletedFor'] ?? const []);
                        return !deletedFor.contains(currentUser!.uid);
                      }).toList();

                      return ListView.builder(
                        reverse: true,
                        controller: scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final data = messages[index].data()
                              as Map<String, dynamic>;
                          data['messageId'] = messages[index].id;
                          final isMe =
                              data['senderId'] == currentUser!.uid;
                          final time = formatTime(
                              data['timestamp'] as Timestamp?);
                          final type = (data['type'] ?? 'text') as String;
                          final decryptedText = decryptMessage(data);
                          final mediaUrl = data['mediaUrl'] as String?;
                          final storagePath = data['storagePath'] as String?;

                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: GestureDetector(
                              // Long-press delete actions are disabled.
                              onHorizontalDragEnd: (details) {
                                if (details.primaryVelocity != null &&
                                    details.primaryVelocity! > 200) {
                                  _setReply(data);
                                }
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                    vertical: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width *
                                          0.72,
                                ),
                                decoration: BoxDecoration(
                                  color: isMe ? scheme.primary : cardColor,
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(16),
                                    topRight: const Radius.circular(16),
                                    bottomLeft: isMe
                                        ? const Radius.circular(16)
                                        : const Radius.circular(4),
                                    bottomRight: isMe
                                        ? const Radius.circular(4)
                                        : const Radius.circular(16),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.end,
                                  children: [
                                    if (data['replyTo'] != null)
                                      _buildReplyPreview(
                                        Map<String, dynamic>.from(data['replyTo']),
                                        isMe,
                                        onSurface,
                                      ),
                                  if (type == 'text')
                                    Text(
                                      decryptedText,
                                      style: TextStyle(
                                        color: isMe ? Colors.white : onSurface,
                                        fontSize: 15,
                                      ),
                                    )
                                  else if (type == 'image' &&
                                      mediaUrl != null)
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => FullImagePage(
                                              imageUrl: mediaUrl,
                                            ),
                                          ),
                                        );
                                      },
                                      child: ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        child: Image.network(
                                          mediaUrl,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    )
                                  else if (type == 'video' && mediaUrl != null)
                                    _VideoPreview(url: mediaUrl)
                                  else if (type == 'voice' && mediaUrl != null)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            _playingMessageId ==
                                                    messages[index].id
                                                ? Icons.stop
                                                : Icons.play_arrow,
                                            color: isMe
                                                ? Colors.white
                                                : onSurface,
                                          ),
                                          onPressed: () {
                                            if (_playingMessageId ==
                                                messages[index].id) {
                                              _audioPlayer.stop();
                                              setState(() {
                                                _playingMessageId = null;
                                              });
                                            } else {
                                              _playVoiceMessage(
                                                mediaUrl,
                                                messages[index].id,
                                                storagePath: storagePath,
                                              );
                                            }
                                          },
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          "Voice message",
                                          style: TextStyle(
                                            color: isMe
                                                ? Colors.white
                                                : onSurface,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    Text(
                                      "[Unsupported message]",
                                      style: TextStyle(
                                        color: isMe ? Colors.white : onSurface,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          time,
                                          style: TextStyle(
                                            color: (isMe ? Colors.white : onSurface)
                                                .withOpacity(0.65),
                                            fontSize: 10,
                                          ),
                                        ),
                                        if (isMe) ...[
                                          const SizedBox(width: 4),
                                          _buildReadReceipt(data),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

                // ✅ Input box
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  color: cardColor,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_replyingTo != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.brightness == Brightness.dark
                                ? const Color(0xFF3A3A3C)
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Replying to ${_replyingTo!['senderId'] == currentUser!.uid ? 'yourself' : widget.userName}',
                                      style: TextStyle(
                                        color: onSurface,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      _replyingTo!['preview'] ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: subText),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _replyingTo = null;
                                  });
                                },
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                      IconButton(
                        icon: const Icon(Icons.image),
                        color: subText,
                        onPressed: _isBlocked ? null : _pickImage,
                      ),
                      IconButton(
                        icon: const Icon(Icons.videocam),
                        color: subText,
                        onPressed: _isBlocked ? null : _pickVideo,
                      ),
                      if (!_isRecording && _recordedVoicePath == null) ...[
                        IconButton(
                          icon: const Icon(Icons.mic),
                          color: subText,
                          onPressed: _isBlocked ? null : _toggleRecording,
                        ),
                        Expanded(
                          child: TextField(
                            controller: msgController,
                            style: TextStyle(color: onSurface),
                            maxLines: null,
                            decoration: InputDecoration(
                              hintText: _isBlocked
                                  ? "Messaging unavailable"
                                  : "Type a message...",
                              hintStyle: TextStyle(color: subText),
                              filled: true,
                              fillColor: theme.brightness == Brightness.dark
                                  ? const Color(0xFF3A3A3C)
                                  : Colors.grey.shade200,
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 15, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(25),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onSubmitted: (_) => sendMessage(),
                            onChanged: _onTypingChanged,
                            enabled: !_isBlocked,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _isBlocked ? null : sendMessage,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.send,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ] else if (_isRecording) ...[
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: theme.brightness == Brightness.dark
                                  ? const Color(0xFF3A3A3C)
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: _cancelRecording,
                                  child: Icon(
                                    Icons.delete,
                                    color: subText,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _formatRecordTime(),
                                  style: TextStyle(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _toggleRecording,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.stop,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ] else ...[
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: theme.brightness == Brightness.dark
                                  ? const Color(0xFF3A3A3C)
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: _discardRecordedVoice,
                                  child: Icon(
                                    Icons.delete_outline,
                                    color: subText,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Icon(
                                  Icons.mic,
                                  color: scheme.primary,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _recordedVoiceDurationMs == null
                                      ? "Voice message ready"
                                      : "${(_recordedVoiceDurationMs! / 1000).round()}s voice message",
                                  style: TextStyle(
                                    color: onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: (_sendingRecordedVoice || _isBlocked)
                              ? null
                              : _sendRecordedVoice,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: (_sendingRecordedVoice || _isBlocked)
                                  ? scheme.primary.withOpacity(0.5)
                                  : scheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: _sendingRecordedVoice
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.send,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                          ),
                        ),
                      ],
                        ],
                      ),
                    ],
                  ),
                ),

                SizedBox(
                    height: MediaQuery.of(context).padding.bottom),
              ],
            ),
    );
  }
}

class _VideoPreview extends StatefulWidget {
  final String url;

  const _VideoPreview({required this.url});

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
        }
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return Container(
        width: 220,
        height: 160,
        color: Colors.black12,
        child: const Center(child: Icon(Icons.videocam)),
      );
    }

    return GestureDetector(
      onTap: () {
        if (controller.value.isPlaying) {
          controller.pause();
        } else {
          controller.play();
        }
        setState(() {});
      },
      child: SizedBox(
        width: 220,
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}