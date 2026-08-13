import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'chat_backend.dart';

class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({super.key});

  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  bool _processing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked Users')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ChatBackend.userDoc().snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Unable to load blocked users.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final blocked = List<String>.from(
            snapshot.data?.data()?['blockedUsers'] ?? const [],
          );
          if (blocked.isEmpty) {
            return const Center(child: Text('No blocked users'));
          }
          return ListView.builder(
            itemCount: blocked.length,
            itemBuilder: (context, index) {
              final uid = blocked[index];
              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: ChatBackend.userDoc(uid).get(),
                builder: (context, userSnapshot) {
                  final data = userSnapshot.data?.data();
                  final name = data?['name'] ?? 'Unknown';
                  final email = data?['email'] ?? '';
                  return ListTile(
                    leading: CircleAvatar(child: Text(name[0].toUpperCase())),
                    title: Text(name),
                    subtitle: Text(email),
                    trailing: TextButton(
                      onPressed: _processing
                          ? null
                          : () async {
                              setState(() => _processing = true);
                              try {
                                await ChatBackend.unblockUser(uid);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('User unblocked'),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Unblock failed: $e'),
                                    ),
                                  );
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => _processing = false);
                                }
                              }
                            },
                      child: Text(_processing ? 'Please wait...' : 'Unblock'),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
