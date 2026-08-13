import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'chat_backend.dart';

class UserProfilePage extends StatefulWidget {
  final String userId;

  const UserProfilePage({
    super.key,
    required this.userId,
  });

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  late Future<Map<String, dynamic>> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfileData();
  }

  Future<Map<String, dynamic>> _loadProfileData() async {
    final targetSnap = await ChatBackend.userDoc(widget.userId).get();
    final mySnap = await ChatBackend.userDoc().get();
    return {
      'target': targetSnap.data(),
      'me': mySnap.data(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!['target'] as Map<String, dynamic>?;
          final me = snapshot.data!['me'] as Map<String, dynamic>? ?? {};

          if (data == null) {
            return const Center(child: Text('Profile not found'));
          }

          final theirBlocked = List<String>.from(data['blockedUsers'] ?? const []);
          final myBlocked = List<String>.from(me['blockedUsers'] ?? const []);
          final blockedByThem = theirBlocked.contains(ChatBackend.currentUid);
          final iBlockedThem = myBlocked.contains(widget.userId);

          if (blockedByThem) {
            return const Center(child: Text('Profile unavailable'));
          }

          final visibility = Map<String, dynamic>.from(
            data['visibility'] ??
                const {
                  'showName': true,
                  'showPhone': true,
                  'showEmail': true,
                },
          );
          final showName = visibility['showName'] == true;
          final showPhone = visibility['showPhone'] == true;
          final showEmail = visibility['showEmail'] == true;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CircleAvatar(
                radius: 36,
                child: Text((data['name'] ?? 'U')[0].toUpperCase()),
              ),
              const SizedBox(height: 16),
              if (showName) ListTile(title: const Text('Username'), subtitle: Text(data['name'] ?? '')),
              if (showPhone) ListTile(title: const Text('Phone'), subtitle: Text(data['phone'] ?? '')),
              if (showEmail) ListTile(title: const Text('Email'), subtitle: Text(data['email'] ?? '')),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  final action = iBlockedThem ? 'unblock' : 'block';
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(iBlockedThem ? 'Unblock user' : 'Block user'),
                      content: Text(
                        iBlockedThem
                            ? 'Do you want to unblock this user?'
                            : 'Do you want to block this user?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(iBlockedThem ? 'Unblock' : 'Block'),
                        ),
                      ],
                    ),
                  );

                  if (confirmed != true) return;

                  if (action == 'unblock') {
                    await ChatBackend.unblockUser(widget.userId);
                  } else {
                    await ChatBackend.blockUser(widget.userId);
                  }

                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        iBlockedThem ? 'User unblocked' : 'User blocked',
                      ),
                    ),
                  );
                  setState(() {
                    _profileFuture = _loadProfileData();
                  });
                  if (!iBlockedThem) {
                    Navigator.pop(context);
                  }
                },
                icon: Icon(iBlockedThem ? Icons.lock_open : Icons.block),
                label: Text(iBlockedThem ? 'Unblock User' : 'Block User'),
              ),
            ],
          );
        },
      ),
    );
  }
}
