import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'chat_page.dart';
import 'add_user_page.dart';
import 'chat_backend.dart';
import 'notification_service.dart';
import 'requests_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const primaryRed = Color(0xFFE63946);

  final currentUser = FirebaseAuth.instance.currentUser;
  String searchQuery = "";
  String currentUserName = "";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setOnlineStatus(true);
    _loadCurrentUserName();
    NotificationService.syncCurrentUserToken();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setOnlineStatus(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setOnlineStatus(true);
    } else {
      _setOnlineStatus(false);
    }
  }

  Future<void> _loadCurrentUserName() async {
    if (currentUser == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser!.uid)
          .get();
      if (doc.exists && mounted) {
        setState(() {
          currentUserName = doc.data()?['name'] ?? '';
        });
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> _setOnlineStatus(bool isOnline) async {
    if (currentUser == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser!.uid)
          .update({
        'isOnline': isOnline,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // ignore
    }
  }

  Future<void> logout() async {
    await _setOnlineStatus(false);
    await FirebaseAuth.instance.signOut();
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _confirmDeleteChat({
    required String otherUserId,
    required String name,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete chat'),
          content: Text('Delete the entire conversation with $name?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await ChatBackend.deleteChatCompletely(otherUserId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chat deleted')),
        );
      }
    }
  }

  // ✅ Show profile popup
  void _showProfileMenu(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = theme.cardColor;
    final muted = (theme.textTheme.bodySmall?.color ?? theme.colorScheme.onSurface)
        .withOpacity(0.7);

    final RenderBox button =
        context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
            button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu(
      context: context,
      position: position,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      items: [
        // ── Profile header ──
        PopupMenuItem(
          enabled: false,
          child: Column(
            children: [
              // Avatar
              CircleAvatar(
                backgroundColor: primaryRed,
                radius: 30,
                child: Text(
                  currentUserName.isNotEmpty
                      ? currentUserName[0].toUpperCase()
                      : (currentUser?.email?[0].toUpperCase() ?? 'U'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Name
              Text(
                currentUserName.isNotEmpty ? currentUserName : 'User',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              // Email
              Text(
                currentUser?.email ?? '',
                style: TextStyle(
                  color: muted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              const Divider(color: Colors.white12),
            ],
          ),
        ),

        // ── Logout option ──
        PopupMenuItem(
          onTap: logout,
          child: Row(
            children: [
              Icon(Icons.logout, color: Theme.of(context).colorScheme.primary, size: 20),
              const SizedBox(width: 12),
              Text(
                "Logout",
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String formatTime(Timestamp? timestamp) {
    if (timestamp == null) return "";
    final dt = timestamp.toDate();
    final now = DateTime.now();
    if (dt.day == now.day &&
        dt.month == now.month &&
        dt.year == now.year) {
      return DateFormat('h:mm a').format(dt);
    }
    return DateFormat('dd/MM').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cardColor = theme.cardColor;
    final muted =
        (theme.textTheme.bodySmall?.color ?? scheme.onSurface).withOpacity(0.7);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,

      appBar: AppBar(
  backgroundColor: theme.appBarTheme.backgroundColor,
  automaticallyImplyLeading: false,
  title: const Text(
    "SecureChat",
    style: TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 22,
    ),
  ),
  actions: [
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ChatBackend.requestCollection()
          .where('toUserId', isEqualTo: currentUser!.uid)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return IconButton(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.mark_email_unread_outlined),
              if (count > 0)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RequestsPage()),
            );
          },
        );
      },
    ),
    // ✅ SETTINGS BUTTON
    IconButton(
      icon: const Icon(Icons.settings),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const SettingsPage(),
          ),
        );
      },
    ),

    // ✅ PROFILE AVATAR
    Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Builder(
        builder: (context) => GestureDetector(
          onTap: () => _showProfileMenu(context),
          child: CircleAvatar(
            backgroundColor: scheme.primary,
            radius: 18,
            child: Text(
              currentUserName.isNotEmpty
                  ? currentUserName[0].toUpperCase()
                  : (currentUser?.email?[0].toUpperCase() ?? 'U'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    ),
  ],
),

      floatingActionButton: FloatingActionButton(
        backgroundColor: scheme.primary,
        child: const Icon(Icons.person_add, color: Colors.white),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddUserPage()),
          );
        },
      ),

      body: Column(
        children: [

          // ✅ Search Bar (now functional)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              style: TextStyle(color: scheme.onSurface),
              onChanged: (val) => setState(() => searchQuery = val),
              decoration: InputDecoration(
                hintText: "Search chats...",
                hintStyle: TextStyle(color: muted),
                prefixIcon:
                    Icon(Icons.search, color: muted),
                filled: true,
                fillColor: cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // ✅ Chat List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .where('participants', arrayContains: currentUser!.uid)
                  .snapshots(),
              builder: (context, chatSnapshot) {
                if (chatSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: primaryRed),
                  );
                }

                if (chatSnapshot.hasError) {
                  return Center(
                    child: Text(
                      "Error: ${chatSnapshot.error}",
                      style: const TextStyle(color: Colors.white54),
                    ),
                  );
                }

                if (!chatSnapshot.hasData ||
                    chatSnapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.chat_bubble_outline,
                            color: Colors.white24, size: 80),
                        const SizedBox(height: 16),
                        const Text(
                          "No chats yet!",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Tap + to find and chat with users",
                          style: TextStyle(color: Colors.white54),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryRed,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.person_add,
                              color: Colors.white),
                          label: const Text(
                            "Add User",
                            style: TextStyle(color: Colors.white),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const AddUserPage()),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                }

                var chats = chatSnapshot.data!.docs;

                chats.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aTime = aData['lastMessageTime'] as Timestamp?;
                  final bTime = bData['lastMessageTime'] as Timestamp?;
                  if (aTime == null) return 1;
                  if (bTime == null) return -1;
                  return bTime.compareTo(aTime);
                });

                return ListView.builder(
                  itemCount: chats.length,
                  itemBuilder: (context, index) {
                    final chatData =
                        chats[index].data() as Map<String, dynamic>;
                    final accepted = chatData['requestAccepted'] != false;
                    if (!accepted) return const SizedBox.shrink();

                    List participants = chatData['participants'] ?? [];
                    String otherUserId = participants.firstWhere(
                      (id) => id != currentUser!.uid,
                      orElse: () => '',
                    );

                    if (otherUserId.isEmpty) return const SizedBox();

                    String lastMessage = chatData['lastMessage'] ?? '';
                    Timestamp? lastMessageTime =
                        chatData['lastMessageTime'] as Timestamp?;

                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .doc(otherUserId)
                          .get(),
                      builder: (context, userSnapshot) {
                        if (!userSnapshot.hasData) return const SizedBox();

                        final userData = userSnapshot.data!.data()
                            as Map<String, dynamic>?;
                        if (userData == null) return const SizedBox();

                        String name = userData['name'] ?? 'Unknown';
                        String phone = (userData['phone'] ?? '') as String;
                        bool isOnline = userData['isOnline'] ?? false;
                        String profileImage = userData['profileImage'] ?? '';
                        final myBlocked = List<String>.from(
                          userData['blockedUsers'] ?? const [],
                        );
                        if (myBlocked.contains(currentUser!.uid)) {
                          return const SizedBox.shrink();
                        }

                        final q = searchQuery.trim().toLowerCase();
                        if (q.isNotEmpty &&
                            !name.toLowerCase().contains(q) &&
                            !phone.toLowerCase().contains(q)) {
                          return const SizedBox();
                        }

                        return Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            leading: Stack(
                              children: [
                                CircleAvatar(
                                  backgroundColor: primaryRed,
                                  radius: 26,
                                  backgroundImage: profileImage.isNotEmpty
                                      ? NetworkImage(profileImage)
                                      : null,
                                  child: profileImage.isEmpty
                                      ? Text(
                                          name[0].toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 20,
                                          ),
                                        )
                                      : null,
                                ),
                                if (isOnline)
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: cardColor, width: 2),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            title: Text(
                              name,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Text(
                              lastMessage.isEmpty ? "Tap to chat" : lastMessage,
                              style: TextStyle(color: muted, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              formatTime(lastMessageTime),
                              style: const TextStyle(
                                  color: primaryRed, fontSize: 11),
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatPage(
                                    userName: name,
                                    userId: otherUserId,
                                  ),
                                ),
                              );
                            },
                            onLongPress: () => _confirmDeleteChat(
                              otherUserId: otherUserId,
                              name: name,
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}