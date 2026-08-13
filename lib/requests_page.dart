import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'chat_backend.dart';
import 'chat_page.dart';

class RequestsPage extends StatelessWidget {
  const RequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Requests')),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const Material(
              child: TabBar(
                tabs: [
                  Tab(text: 'Received'),
                  Tab(text: 'Sent'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _ReceivedRequestsList(uid: ChatBackend.currentUid),
                  _SentRequestsList(uid: ChatBackend.currentUid),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceivedRequestsList extends StatelessWidget {
  const _ReceivedRequestsList({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ChatBackend.requestCollection()
          .where('toUserId', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Unable to load received requests.\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const Center(child: Text('No pending received requests'));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final fromUserId = data['fromUserId'] as String? ?? '';
            final fromName = (data['fromName'] as String?)?.trim().isNotEmpty == true
                ? (data['fromName'] as String).trim()
                : 'Unknown';
            final fromEmail = (data['fromEmail'] as String?)?.trim() ?? '';
            final avatarLetter =
                fromName.isNotEmpty ? fromName[0].toUpperCase() : '?';

            return ListTile(
              leading: CircleAvatar(child: Text(avatarLetter)),
              title: Text(fromName),
              subtitle: Text(fromEmail),
              trailing: Wrap(
                spacing: 8,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: fromUserId.isEmpty
                        ? null
                        : () => ChatBackend.rejectRequest(fromUserId),
                  ),
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: fromUserId.isEmpty
                        ? null
                        : () async {
                            await ChatBackend.acceptRequest(
                              fromUserId: fromUserId,
                              fromName: fromName,
                            );
                            if (!context.mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatPage(
                                  userName: fromName,
                                  userId: fromUserId,
                                ),
                              ),
                            );
                          },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SentRequestsList extends StatelessWidget {
  const _SentRequestsList({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ChatBackend.requestCollection()
          .where('fromUserId', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Unable to load sent requests.\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const Center(child: Text('No pending sent requests'));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final toUserId = data['toUserId'] as String? ?? '';
            final toName = (data['toName'] as String?)?.trim().isNotEmpty == true
                ? (data['toName'] as String).trim()
                : 'Unknown';
            final toEmail = (data['toEmail'] as String?)?.trim() ?? '';
            final avatarLetter = toName.isNotEmpty ? toName[0].toUpperCase() : '?';

            return ListTile(
              leading: CircleAvatar(child: Text(avatarLetter)),
              title: Text(toName),
              subtitle: Text(toEmail),
              trailing: TextButton(
                onPressed: toUserId.isEmpty
                    ? null
                    : () => ChatBackend.cancelRequest(toUserId: toUserId),
                child: const Text('Cancel'),
              ),
            );
          },
        );
      },
    );
  }
}
