import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class VerifyEmailPage extends StatefulWidget {
  final String email;

  const VerifyEmailPage({
    super.key,
    this.email = '',
  });

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  bool _sending = false;
  bool _checking = false;

  Future<void> _resend() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please login again to resend email')),
        );
      }
      return;
    }
    setState(() => _sending = true);
    try {
      await user.sendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification email sent')),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Failed to send email')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _checkVerified() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session expired. Please login again.')),
        );
        Navigator.pushReplacementNamed(context, '/login');
      }
      return;
    }
    setState(() => _checking = true);
    try {
      await user.reload();
      final refreshed = FirebaseAuth.instance.currentUser;
      if (refreshed?.emailVerified == true) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Not verified yet. Check your inbox.')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onSurface = scheme.onSurface;
    final user = FirebaseAuth.instance.currentUser;
    final email = widget.email.isNotEmpty
        ? widget.email
        : (user?.email ?? '');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Email'),
        actions: [
          TextButton(
            onPressed: _logout,
            child: Text(
              'Logout',
              style: TextStyle(color: scheme.primary),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'We sent a verification link to:',
              style: TextStyle(
                color: onSurface.withOpacity(0.75),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              email,
              style: TextStyle(
                color: onSurface,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Open your email and click the verification link. Then come back and tap “I verified”.',
              style: TextStyle(
                color: onSurface.withOpacity(0.8),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            if (user == null) ...[
              Text(
                'You are signed out. Please login again to verify your email.',
                style: TextStyle(
                  color: onSurface.withOpacity(0.8),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                  child: const Text('Go to login'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: (user == null || _checking) ? null : _checkVerified,
                child: _checking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('I verified'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: (user == null || _sending) ? null : _resend,
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Resend email'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

