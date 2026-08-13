import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PhoneOtpPage extends StatefulWidget {
  final String phoneNumber; // E.164 format (+...)

  const PhoneOtpPage({
    super.key,
    required this.phoneNumber,
  });

  @override
  State<PhoneOtpPage> createState() => _PhoneOtpPageState();
}

class _PhoneOtpPageState extends State<PhoneOtpPage> {
  final TextEditingController _codeController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _verificationId;
  bool _verifying = false;
  bool _sending = false;
  bool _canResend = false;
  int _secondsRemaining = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startPhoneVerification();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() {
      _secondsRemaining = 60;
      _canResend = false;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() {
          _canResend = true;
        });
      } else {
        setState(() {
          _secondsRemaining--;
        });
      }
    });
  }

  Future<void> _startPhoneVerification() async {
    setState(() {
      _sending = true;
    });
    await _auth.verifyPhoneNumber(
      phoneNumber: widget.phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Auto-retrieval (Android). We can sign in silently, but here we just
        // complete the flow and pop with success.
        try {
          await _auth.signInWithCredential(credential);
        } catch (_) {
          // ignore auth error here; user can still enter code manually
        }
        if (mounted) {
          Navigator.of(context).pop<bool>(true);
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!mounted) return;
        final isProviderDisabled =
            e.code == 'operation-not-allowed' || e.code == 'provider-disabled';
        final isInvalidPhone =
            e.code == 'invalid-phone-number' || e.code == 'invalid-phone';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isProviderDisabled
                  ? 'Phone sign-in is disabled for this Firebase project. Enable Phone in Firebase Console → Authentication → Sign-in method.'
                  : isInvalidPhone
                      ? 'Invalid phone number. Use E.164 format like +919876543210 (country code + number).'
                  : (e.message ?? 'Phone verification failed'),
            ),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _sending = false;
        });
      },
      codeSent: (String verificationId, int? resendToken) {
        setState(() {
          _verificationId = verificationId;
          _sending = false;
        });
        _startTimer();
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        setState(() {
          _verificationId = verificationId;
          _canResend = true;
        });
      },
    );
  }

  Future<void> _verifyCode() async {
    if (_verificationId == null || _codeController.text.trim().length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit code')),
      );
      return;
    }

    setState(() {
      _verifying = true;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _codeController.text.trim(),
      );
      await _auth.signInWithCredential(credential);
      if (mounted) {
        Navigator.of(context).pop<bool>(true);
      }
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Invalid code'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _verifying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Phone'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A 6-digit code has been sent to',
              style: TextStyle(
                color: onSurface.withOpacity(0.8),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.phoneNumber,
              style: TextStyle(
                color: onSurface,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Enter 6-digit OTP',
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _verifying ? null : _verifyCode,
                child: _verifying
                    ? const CircularProgressIndicator(
                        color: Colors.white,
                      )
                    : const Text('Verify'),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _canResend
                      ? 'Didn\'t get the code?'
                      : 'Resend code in $_secondsRemaining s',
                  style: TextStyle(
                    color: onSurface.withOpacity(0.7),
                  ),
                ),
                if (_canResend)
                  TextButton(
                    onPressed: _sending ? null : _startPhoneVerification,
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Resend'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

