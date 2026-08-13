import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatBackend {
  ChatBackend._();

  static final FirebaseFirestore firestore = FirebaseFirestore.instance;
  static final FirebaseAuth auth = FirebaseAuth.instance;

  static String get currentUid => auth.currentUser!.uid;

  static String chatIdFor(String a, String b) {
    final ids = [a, b]..sort();
    return ids.join('_');
  }

  static DocumentReference<Map<String, dynamic>> userDoc([String? uid]) {
    return firestore.collection('users').doc(uid ?? currentUid);
  }

  static DocumentReference<Map<String, dynamic>> chatDoc(String otherUserId) {
    return firestore.collection('chats').doc(chatIdFor(currentUid, otherUserId));
  }

  static CollectionReference<Map<String, dynamic>> requestCollection() {
    return firestore.collection('chat_requests');
  }

  static String requestIdFor(String fromUserId, String toUserId) {
    final ids = [fromUserId, toUserId]..sort();
    return ids.join('_');
  }

  static Future<Map<String, dynamic>?> currentUserData() async {
    final snap = await userDoc().get();
    return snap.data();
  }

  static Future<bool> isBlockedEitherWay(String otherUserId) async {
    final mySnap = await userDoc().get();
    final otherSnap = await userDoc(otherUserId).get();
    final myBlocked = List<String>.from(mySnap.data()?['blockedUsers'] ?? const []);
    final theirBlocked =
        List<String>.from(otherSnap.data()?['blockedUsers'] ?? const []);
    return myBlocked.contains(otherUserId) || theirBlocked.contains(currentUid);
  }

  static Future<void> sendChatRequest({
    required String toUserId,
    required String toName,
    required String toEmail,
  }) async {
    final me = await currentUserData();
    if (me == null) return;

    final requestId = requestIdFor(currentUid, toUserId);
    await requestCollection().doc(requestId).set({
      'id': requestId,
      'fromUserId': currentUid,
      'toUserId': toUserId,
      'fromName': me['name'] ?? '',
      'fromEmail': me['email'] ?? '',
      'toName': toName,
      'toEmail': toEmail,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> acceptRequest({
    required String fromUserId,
    required String fromName,
  }) async {
    final requestId = requestIdFor(currentUid, fromUserId);
    final chatId = chatIdFor(currentUid, fromUserId);
    await firestore.runTransaction((txn) async {
      txn.set(requestCollection().doc(requestId), {
        'status': 'accepted',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      txn.set(firestore.collection('chats').doc(chatId), {
        'participants': [currentUid, fromUserId],
        'requestAccepted': true,
        'acceptedUsers': [currentUid, fromUserId],
        'typing': {
          currentUid: false,
          fromUserId: false,
        },
        'deletedFor': <String>[],
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  static Future<void> rejectRequest(String fromUserId) async {
    final requestId = requestIdFor(currentUid, fromUserId);
    await requestCollection().doc(requestId).set({
      'status': 'rejected',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> cancelRequest({required String toUserId}) async {
    final requestId = requestIdFor(currentUid, toUserId);
    await requestCollection().doc(requestId).set({
      'status': 'cancelled',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> ensureAcceptedChat(String otherUserId) async {
    final chatId = chatIdFor(currentUid, otherUserId);
    await firestore.collection('chats').doc(chatId).set({
      'participants': [currentUid, otherUserId],
      'requestAccepted': true,
      'acceptedUsers': [currentUid, otherUserId],
      'typing': {
        currentUid: false,
        otherUserId: false,
      },
      'deletedFor': <String>[],
    }, SetOptions(merge: true));
  }

  static Future<void> setTyping(String otherUserId, bool isTyping) async {
    await chatDoc(otherUserId).set({
      'participants': [currentUid, otherUserId],
      'typing': {
        currentUid: isTyping,
      },
    }, SetOptions(merge: true));
  }

  static Future<void> deleteChatCompletely(String otherUserId) async {
    final chatRef = chatDoc(otherUserId);
    final messages = await chatRef.collection('messages').get();
    final batch = firestore.batch();
    for (final doc in messages.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(chatRef);
    await batch.commit();
  }

  static Future<void> blockUser(String otherUserId) async {
    await userDoc().set({
      'blockedUsers': FieldValue.arrayUnion([otherUserId]),
    }, SetOptions(merge: true));
  }

  static Future<void> unblockUser(String otherUserId) async {
    await userDoc().set({
      'blockedUsers': FieldValue.arrayRemove([otherUserId]),
    }, SetOptions(merge: true));
  }

  static Future<void> updateVisibility({
    required bool showName,
    required bool showPhone,
    required bool showEmail,
  }) async {
    await userDoc().set({
      'visibility': {
        'showName': showName,
        'showPhone': showPhone,
        'showEmail': showEmail,
      },
    }, SetOptions(merge: true));
  }

  static Future<void> updateUsernameOnce(String name) async {
    final snap = await userDoc().get();
    final data = snap.data() ?? {};
    if (data['usernameChanged'] == true) {
      throw Exception('Username can only be changed once');
    }
    await userDoc().set({
      'name': name,
      'usernameChanged': true,
    }, SetOptions(merge: true));
  }

  static Future<void> setNotificationsEnabled(bool enabled) async {
    await userDoc().set({
      'notificationsEnabled': enabled,
    }, SetOptions(merge: true));
  }
}
