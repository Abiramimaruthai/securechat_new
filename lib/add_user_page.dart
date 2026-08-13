import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'chat_backend.dart';

class AddUserPage extends StatefulWidget {
  const AddUserPage({super.key});

  @override
  State<AddUserPage> createState() => _AddUserPageState();
}

class _AddUserPageState extends State<AddUserPage> {
  final queryController = TextEditingController();
  static const primaryRed = Color(0xFFE63946);
  static const bg = Color(0xFF1A1A1A);
  static const card = Color(0xFF2C2C2E);

  bool loading = false;
  Map<String, dynamic>? foundUser;

  final currentUser = FirebaseAuth.instance.currentUser;

  Future<void> searchUser() async {
    if (queryController.text.trim().isEmpty) return;

    setState(() {
      loading = true;
      foundUser = null;
    });

    try {
      final q = queryController.text.trim();
      final qLower = q.toLowerCase();
      final phoneDigits = q.replaceAll(RegExp(r'\D'), '');
      final isEmailQuery = q.contains('@');
      final isProbablyPhone = !isEmailQuery && phoneDigits.length >= 8;

      QuerySnapshot<Map<String, dynamic>> result;
      final users = FirebaseFirestore.instance.collection('users');

      if (isProbablyPhone) {
        // Try normalized phone fields first, then raw phone field.
        result = await users.where('phoneDigits', isEqualTo: phoneDigits).get();
        if (result.docs.isEmpty) {
          result = await users.where('phone', isEqualTo: phoneDigits).get();
        }
        if (result.docs.isEmpty) {
          result = await users.where('phone', isEqualTo: q).get();
        }
      } else {
        // Email lookups are case-sensitive in Firestore, so try variants.
        result = await users.where('emailLower', isEqualTo: qLower).get();
        if (result.docs.isEmpty) {
          result = await users.where('email', isEqualTo: q).get();
        }
        if (result.docs.isEmpty && qLower != q) {
          result = await users.where('email', isEqualTo: qLower).get();
        }
      }

      if (result.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("No user found with this email/number")),
        );
      } else {
        final data = result.docs.first.data();
        if (data['uid'] == currentUser!.uid) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("That's your own account!")),
          );
        } else {
          setState(() => foundUser = data);
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }

    setState(() => loading = false);
  }

  Future<void> sendRequest() async {
    if (foundUser == null) return;

    final otherUserId = foundUser!['uid'];

    try {
      final blocked = await ChatBackend.isBlockedEitherWay(otherUserId);
      if (blocked) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Cannot send request to this user")),
          );
        }
        return;
      }

      await ChatBackend.sendChatRequest(
        toUserId: otherUserId,
        toName: foundUser!['name'] ?? '',
        toEmail: foundUser!['email'] ?? '',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Chat request sent")),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error sending request: $e")),
      );
    }
  }

  @override
  void dispose() {
    queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF2C2C2E),
        title: const Text(
          "Add User",
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: queryController,
              keyboardType: TextInputType.text,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Enter email or mobile number",
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon:
                    const Icon(Icons.search, color: Colors.white54),
                filled: true,
                fillColor: card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryRed,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: loading ? null : searchUser,
                child: loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "Search User",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 24),

            if (foundUser != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: primaryRed,
                      radius: 28,
                      child: Text(
                        foundUser!['name'][0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            foundUser!['name'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            foundUser!['email'],
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryRed,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: sendRequest,
                      child: const Text(
                        "Request",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}