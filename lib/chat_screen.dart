import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'app_settings.dart';

class ChatScreen extends StatefulWidget {
  final String chatRoomId;
  final String receiverName;
  final String receiverEmail;

  const ChatScreen({
    super.key,
    required this.chatRoomId,
    required this.receiverName,
    required this.receiverEmail,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController messageController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final currentUser = FirebaseAuth.instance.currentUser;
  final ImagePicker _imagePicker = ImagePicker();
  bool _showEmoji = false;
  bool _cleaning = false;

  @override
  void dispose() {
    messageController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _cleanupExpiredMessages();
  }

  Future<void> _cleanupExpiredMessages() async {
    if (_cleaning) return;
    _cleaning = true;
    try {
      final now = Timestamp.now();
      final q = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatRoomId)
          .collection('messages')
          .where('expiresAt', isLessThanOrEqualTo: now)
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

  Future<void> sendMessage() async {
    if (messageController.text.trim().isEmpty) return;

    final text = messageController.text.trim();
    messageController.clear();

    await _sendMessageDoc({
      'type': 'text',
      'text': text,
    });
  }

  Future<void> _sendMessageDoc(Map<String, dynamic> payload) async {
    final expiresAt = (AppSettings.selfDestructEnabled.value &&
            AppSettings.selfDestructSeconds.value > 0)
        ? Timestamp.fromDate(
            DateTime.now().add(Duration(seconds: AppSettings.selfDestructSeconds.value)),
          )
        : null;

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatRoomId)
        .collection('messages')
        .add({
      ...payload,
      'isDeleted': false,
      'deletedFor': <String>[],
      'sender': currentUser!.email,
      'senderId': currentUser!.uid,
      'time': FieldValue.serverTimestamp(),
      if (expiresAt != null) 'expiresAt': expiresAt,
    });

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatRoomId)
        .set({
      'lastMessage': payload['type'] == 'text'
          ? (payload['text'] ?? '')
          : payload['type'] == 'image'
              ? '📷 Photo'
              : '📎 File',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'participants': [currentUser!.uid],
    }, SetOptions(merge: true));
  }

  Future<void> _sendImage() async {
    final x = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (x == null) return;

    final bytes = await x.readAsBytes();
    final fileName = x.name.isNotEmpty ? x.name : 'image.jpg';
    final ref = FirebaseStorage.instance
        .ref()
        .child('chats/${widget.chatRoomId}/${DateTime.now().millisecondsSinceEpoch}_$fileName');

    final task = await ref.putData(bytes);
    final url = await task.ref.getDownloadURL();

    await _sendMessageDoc({
      'type': 'image',
      'url': url,
      'name': fileName,
    });
  }

  Future<void> _sendFile() async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    if (res == null || res.files.isEmpty) return;

    final f = res.files.first;
    if (f.bytes == null) return;

    final name = f.name;
    final ref = FirebaseStorage.instance
        .ref()
        .child('chats/${widget.chatRoomId}/${DateTime.now().millisecondsSinceEpoch}_$name');

    final task = await ref.putData(f.bytes!);
    final url = await task.ref.getDownloadURL();

    await _sendMessageDoc({
      'type': 'file',
      'url': url,
      'name': name,
      'size': f.size,
    });
  }

  Future<void> _deleteForMe(DocumentReference ref) async {
    await ref.update({
      'deletedFor': FieldValue.arrayUnion([currentUser!.uid]),
    });
  }

  Future<void> _deleteForEveryone(DocumentReference ref) async {
    await ref.update({
      'isDeleted': true,
      'text': '',
      'type': 'text',
    });
  }

  void _showMessageActions({
    required bool isMe,
    required DocumentReference ref,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete for me'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _deleteForMe(ref);
                },
              ),
              if (isMe)
                ListTile(
                  leading: const Icon(Icons.delete_forever),
                  title: const Text('Delete for everyone'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _deleteForEveryone(ref);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  String formatTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final dt = timestamp.toDate();
    return DateFormat('h:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final onSurface = scheme.onSurface;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: scheme.primary,
              radius: 18,
              child: Text(
                widget.receiverName.isNotEmpty
                    ? widget.receiverName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.receiverName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.receiverEmail,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.chatRoomId)
                  .collection('messages')
                  .orderBy('time', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: scheme.primary),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet.\nSay Hello!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.color
                            ?.withOpacity(0.7),
                      ),
                    ),
                  );
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  reverse: true,
                  controller: scrollController,
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final isMe = data['senderId'] == currentUser!.uid;
                    final time = formatTime(data['time'] as Timestamp?);
                    final deletedFor = (data['deletedFor'] as List?) ?? const [];
                    if (deletedFor.contains(currentUser!.uid)) {
                      return const SizedBox.shrink();
                    }

                    final expiresAt = data['expiresAt'] as Timestamp?;
                    if (expiresAt != null && expiresAt.compareTo(Timestamp.now()) <= 0) {
                      // expired; hide (cleanup runs separately)
                      return const SizedBox.shrink();
                    }

                    final type = (data['type'] ?? 'text') as String;
                    final isDeleted = (data['isDeleted'] ?? false) as bool;

                    return Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: () => _showMessageActions(
                          isMe: isMe,
                          ref: doc.reference,
                        ),
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 12,
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 14,
                          ),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.72,
                          ),
                          decoration: BoxDecoration(
                            color: isMe ? scheme.primary : theme.cardColor,
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
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (isDeleted)
                                Text(
                                  'Message deleted',
                                  style: TextStyle(
                                    color: (isMe ? Colors.white : onSurface)
                                        .withOpacity(0.75),
                                    fontStyle: FontStyle.italic,
                                    fontSize: 14,
                                  ),
                                )
                              else if (type == 'image')
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    data['url'] ?? '',
                                    fit: BoxFit.cover,
                                  ),
                                )
                              else if (type == 'file')
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.insert_drive_file, color: Colors.white),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        data['name'] ?? 'File',
                                        style: TextStyle(
                                          color: isMe ? Colors.white : onSurface,
                                          fontSize: 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Text(
                                  data['text'] ?? '',
                                  style: TextStyle(
                                    color: isMe ? Colors.white : onSurface,
                                    fontSize: 15,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Text(
                                time,
                                style: TextStyle(
                                  color: (isMe ? Colors.white : onSurface)
                                      .withOpacity(0.65),
                                  fontSize: 10,
                                ),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: Theme.of(context).cardColor,
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.emoji_emotions_outlined,
                    color: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.color
                        ?.withOpacity(0.6),
                  ),
                  onPressed: () {
                    setState(() {
                      _showEmoji = !_showEmoji;
                    });
                  },
                ),
                IconButton(
                  icon: Icon(
                    Icons.attach_file,
                    color: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.color
                        ?.withOpacity(0.6),
                  ),
                  onPressed: () async {
                    final choice = await showModalBottomSheet<String>(
                      context: context,
                      builder: (ctx) {
                        return SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: const Icon(Icons.image),
                                title: const Text('Send photo'),
                                onTap: () => Navigator.pop(ctx, 'image'),
                              ),
                              ListTile(
                                leading: const Icon(Icons.insert_drive_file),
                                title: const Text('Send file'),
                                onTap: () => Navigator.pop(ctx, 'file'),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                    if (choice == 'image') {
                      await _sendImage();
                    } else if (choice == 'file') {
                      await _sendFile();
                    }
                  },
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF3A3A3C)
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: messageController,
                      style: TextStyle(color: onSurface),
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(color: onSurface.withOpacity(0.6)),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: sendMessage,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.send,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_showEmoji)
            SizedBox(
              height: 260,
              child: EmojiPicker(
                textEditingController: messageController,
                config: Config(
                  emojiViewConfig: EmojiViewConfig(
                    backgroundColor: theme.scaffoldBackgroundColor,
                  ),
                ),
              ),
            ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
