import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'chat_backend.dart';
import 'chat_page.dart';

class NotificationService {
  NotificationService._();

  static final navigatorKey = GlobalKey<NavigatorState>();
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static const AndroidNotificationChannel _messageChannel =
      AndroidNotificationChannel(
    'messages',
    'Messages',
    description: 'New chat message alerts',
    importance: Importance.high,
  );

  static Future<void> initialize() async {
    await FirebaseMessaging.instance.requestPermission();
    await syncCurrentUserToken();
    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      await ChatBackend.userDoc().set({
        'fcmTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));
    });

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _local.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) {
          final data = jsonDecode(response.payload!) as Map<String, dynamic>;
          _openChatFromPayload(data);
        }
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_messageChannel);
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    FirebaseMessaging.onMessage.listen((message) async {
      final me = await ChatBackend.userDoc().get();
      if (me.data()?['notificationsEnabled'] == false) return;
      final title = message.notification?.title ?? 'SecureChat';
      final body = message.notification?.body ?? 'You have a new message';
      await _local.show(
        message.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _messageChannel.id,
            _messageChannel.name,
            channelDescription: _messageChannel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: jsonEncode(message.data),
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteMessage);
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleRemoteMessage(initialMessage);
    }
  }

  static Future<void> syncCurrentUserToken() async {
    if (ChatBackend.auth.currentUser == null) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    await ChatBackend.userDoc().set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }

  static Future<void> _handleRemoteMessage(RemoteMessage message) async {
    _openChatFromPayload(message.data);
  }

  static Future<void> _openChatFromPayload(Map<String, dynamic> data) async {
    final userId = data['userId'] as String?;
    if (userId == null) return;
    final userSnap = await ChatBackend.userDoc(userId).get();
    final userName = userSnap.data()?['name'] ?? 'User';
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(
      MaterialPageRoute(
        builder: (_) => ChatPage(
          userName: userName,
          userId: userId,
        ),
      ),
    );
  }
}
