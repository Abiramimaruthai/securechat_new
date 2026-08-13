import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'blocked_users_page.dart';
import 'chat_backend.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _selfDestructOptions = <int>[0, 10, 30, 60, 300, 600];
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _changeUsernameOnce(bool alreadyChanged) async {
    if (alreadyChanged) return;
    final value = _nameController.text.trim();
    if (value.isEmpty) return;
    try {
      await ChatBackend.updateUsernameOnce(value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Username updated')),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final subColor = textColor.withOpacity(0.7);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: ChatBackend.userDoc().get(),
        builder: (context, snapshot) {
          final userData = snapshot.data?.data() ?? {};
          final visibility = Map<String, dynamic>.from(
            userData['visibility'] ??
                const {
                  'showName': true,
                  'showPhone': true,
                  'showEmail': true,
                },
          );
          final usernameChanged = userData['usernameChanged'] == true;
          final notificationsEnabled =
              userData['notificationsEnabled'] != false;
          _nameController.text = userData['name'] ?? '';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SettingsCard(
                child: Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      enabled: !usernameChanged,
                      decoration: InputDecoration(
                        labelText: usernameChanged
                            ? 'Username already changed once'
                            : 'Change username once',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: usernameChanged
                            ? null
                            : () => _changeUsernameOnce(usernameChanged),
                        child: const Text('Save username'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Show username', style: TextStyle(color: textColor)),
                      value: visibility['showName'] == true,
                      onChanged: (value) async {
                        await ChatBackend.updateVisibility(
                          showName: value,
                          showPhone: visibility['showPhone'] == true,
                          showEmail: visibility['showEmail'] == true,
                        );
                        setState(() {});
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Show phone', style: TextStyle(color: textColor)),
                      value: visibility['showPhone'] == true,
                      onChanged: (value) async {
                        await ChatBackend.updateVisibility(
                          showName: visibility['showName'] == true,
                          showPhone: value,
                          showEmail: visibility['showEmail'] == true,
                        );
                        setState(() {});
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Show email', style: TextStyle(color: textColor)),
                      value: visibility['showEmail'] == true,
                      onChanged: (value) async {
                        await ChatBackend.updateVisibility(
                          showName: visibility['showName'] == true,
                          showPhone: visibility['showPhone'] == true,
                          showEmail: value,
                        );
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Push notifications', style: TextStyle(color: textColor)),
                  subtitle: Text(
                    'Only show "You have a new message"',
                    style: TextStyle(color: subColor),
                  ),
                  value: notificationsEnabled,
                  onChanged: (value) async {
                    await ChatBackend.setNotificationsEnabled(value);
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Blocked contacts', style: TextStyle(color: textColor)),
                  subtitle: Text(
                    'Manage blocked users',
                    style: TextStyle(color: subColor),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BlockedUsersPage(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                child: ValueListenableBuilder<bool>(
                  valueListenable: AppSettings.appLockEnabled,
                  builder: (context, enabled, _) {
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('App Lock', style: TextStyle(color: textColor)),
                      subtitle: Text(
                        'Require PIN before entering the app',
                        style: TextStyle(color: subColor),
                      ),
                      value: enabled,
                      onChanged: (value) async {
                        await AppSettings.setAppLock(value);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                child: ValueListenableBuilder<bool>(
                  valueListenable: AppSettings.isDarkMode,
                  builder: (context, enabled, _) {
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Dark Theme', style: TextStyle(color: textColor)),
                      subtitle: Text(
                        'Apply theme across the app',
                        style: TextStyle(color: subColor),
                      ),
                      value: enabled,
                      onChanged: (value) async {
                        await AppSettings.setDarkMode(value);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                child: ValueListenableBuilder<bool>(
                  valueListenable: AppSettings.screenshotAllowed,
                  builder: (context, enabled, _) {
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Allow Screenshot',
                        style: TextStyle(color: textColor),
                      ),
                      subtitle: Text(
                        enabled ? 'Screenshots are allowed' : 'Screenshots are blocked',
                        style: TextStyle(color: subColor),
                      ),
                      value: enabled,
                      onChanged: (value) async {
                        await AppSettings.setScreenshotAllowed(value);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                child: ValueListenableBuilder<bool>(
                  valueListenable: AppSettings.selfDestructEnabled,
                  builder: (context, enabled, _) {
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Message Self-Destruct',
                        style: TextStyle(color: textColor),
                      ),
                      subtitle: Text(
                        enabled
                            ? 'Messages auto-delete after the timer'
                            : 'Messages stay until deleted',
                        style: TextStyle(color: subColor),
                      ),
                      value: enabled,
                      onChanged: (value) async {
                        await AppSettings.setSelfDestructEnabled(value);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                child: ValueListenableBuilder<int>(
                  valueListenable: AppSettings.selfDestructSeconds,
                  builder: (context, seconds, _) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Self-Destruct Timer',
                        style: TextStyle(color: textColor),
                      ),
                      subtitle: Text(
                        seconds == 0 ? 'Off' : '$seconds seconds',
                        style: TextStyle(color: subColor),
                      ),
                      trailing: DropdownButton<int>(
                        value: seconds,
                        items: _selfDestructOptions
                            .map(
                              (s) => DropdownMenuItem<int>(
                                value: s,
                                child: Text(s == 0 ? 'Off' : '${s}s'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) async {
                          if (v == null) return;
                          await AppSettings.setSelfDestructSeconds(v);
                          if (v == 0) {
                            await AppSettings.setSelfDestructEnabled(false);
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final Widget child;

  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}
