import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'security/encryption_service.dart';
import 'verify_email_page.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  final Color accentRed = const Color(0xFFE63946);
  bool loading = false;
  bool obscurePassword = true;
  bool obscureConfirm = true;

  // ✅ User picks a number 1-10
  int selectedNumber = 1;

  // ✅ Secret mapping — user never sees this
  final Map<int, String> _secretMap = {
  1: 'ChaCha20',
  2: 'AES',       // ✅ changed from RSA to AES for now
  3: 'AES',
  4: 'ChaCha20',
  5: 'AES',
  6: 'ChaCha20',  // ✅ changed from RSA
  7: 'AES',
  8: 'ChaCha20',
  9: 'AES',       // ✅ changed from RSA
  10: 'AES',
};

  // ✅ Get algorithm from number (hidden from user)
  String get _assignedAlgorithm => _secretMap[selectedNumber] ?? 'AES';

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  String _normalizePhone(String input) {
    return input.replaceAll(RegExp(r'\D'), '');
  }

  String _toE164(String input) {
    // Convert user input to E.164: +<country code><subscriber number>
    // Keep leading '+' if provided; otherwise strip to digits and prepend '+'.
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('+')) {
      final digits = trimmed.substring(1).replaceAll(RegExp(r'\D'), '');
      return digits.isEmpty ? '' : '+$digits';
    }
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    return digits.isEmpty ? '' : '+$digits';
  }

  Future<void> signUp() async {
    setState(() => loading = true);

    try {
      // ✅ Validate
      if (nameController.text.trim().isEmpty) {
        _showSnack("Please enter your name");
        setState(() => loading = false);
        return;
      }
      if (emailController.text.trim().isEmpty) {
        _showSnack("Please enter your email");
        setState(() => loading = false);
        return;
      }
      final phone = _normalizePhone(phoneController.text.trim());
      if (phone.isEmpty) {
        _showSnack("Please enter your mobile number");
        setState(() => loading = false);
        return;
      }
      // basic length check (adjust if you want country-code support)
      if (phone.length < 8 || phone.length > 15) {
        _showSnack("Please enter a valid mobile number");
        setState(() => loading = false);
        return;
      }
      if (passwordController.text.trim().length < 6) {
        _showSnack("Password must be at least 6 characters");
        setState(() => loading = false);
        return;
      }
      if (passwordController.text.trim() !=
          confirmPasswordController.text.trim()) {
        _showSnack("Passwords do not match");
        setState(() => loading = false);
        return;
      }

      // ✅ Create Firebase Auth user
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      // ✅ Generate keys based on SECRET algorithm
      String encryptionKey = '';
      String publicKey = '';
      String privateKey = '';
      String ecdhPublicKey = '';
      String ecdhPrivateKey = '';

      if (_assignedAlgorithm == 'AES') {
  encryptionKey = EncryptionService.generateAESKey();
  publicKey = '';
  privateKey = '';

} else if (_assignedAlgorithm == 'ChaCha20') {
  encryptionKey = EncryptionService.generateChaCha20Key();
  publicKey = '';
  privateKey = '';

} else if (_assignedAlgorithm == 'RSA') {
  try {
    // ✅ RSA generation in background (takes time)
    final keyPair = await Future(
      () => EncryptionService.generateRSAKeyPair()
    );

    publicKey = keyPair['publicKey'] ?? '';
    privateKey = keyPair['privateKey'] ?? '';

    // ✅ If RSA key generation failed → silently use AES
    if (publicKey.isEmpty || privateKey.isEmpty) {
      encryptionKey = EncryptionService.generateAESKey();
      publicKey = '';
      privateKey = '';
    } else {
      encryptionKey = publicKey;
    }

  } catch (e) {
    // ✅ RSA failed → silently fallback to AES
    debugPrint("RSA keygen failed: $e");
    encryptionKey = EncryptionService.generateAESKey();
    publicKey = '';
    privateKey = '';
  }
}

      // ✅ Always generate ECDH (P-256) keys for key agreement
      try {
        final ecdhKeys = EncryptionService.generateEcdhKeyPairP256();
        ecdhPublicKey = ecdhKeys['publicKey'] ?? '';
        ecdhPrivateKey = ecdhKeys['privateKey'] ?? '';
      } catch (e) {
        debugPrint("ECDH keygen failed: $e");
        ecdhPublicKey = '';
        ecdhPrivateKey = '';
      }

      // ✅ Save to Firestore
      // Algorithm is saved but user never sees it in UI
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
        'name': nameController.text.trim(),
        'email': emailController.text.trim(),
        'emailLower': emailController.text.trim().toLowerCase(),
        'phone': phone,
        'phoneDigits': phone.replaceAll(RegExp(r'\D'), ''),
        'uid': userCredential.user!.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
        'profileImage': '',
        'phoneVerified': false,
        'usernameChanged': false,
        'blockedUsers': <String>[],
        'notificationsEnabled': true,
        'visibility': {
          'showName': true,
          'showPhone': true,
          'showEmail': true,
        },
        // ✅ Hidden encryption fields
        'securityNumber': selectedNumber,  // user's chosen number
        'algorithm': _assignedAlgorithm,   // secret algorithm
        'encryptionKey': encryptionKey,
        'publicKey': publicKey,
        'privateKey': privateKey,
        'ecdhPublicKey': ecdhPublicKey,
        'ecdhPrivateKey': ecdhPrivateKey,
      });

      // ✅ Send email verification and move user to verify screen
      String? verificationSendError;
      try {
        await userCredential.user?.sendEmailVerification();
      } on FirebaseAuthException catch (e) {
        verificationSendError = e.message ?? e.code;
      } catch (e) {
        verificationSendError = e.toString();
      }

      if (mounted) {
        _showSnack(
          verificationSendError == null
              ? "Verification email sent. Please verify to continue."
              : "Account created, but email couldn't be sent: $verificationSendError",
          color: verificationSendError == null ? Colors.green : Colors.orange,
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => VerifyEmailPage(
              email: emailController.text.trim(),
            ),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = "Signup failed";
      if (e.code == 'email-already-in-use') {
        message = "Email already in use";
      } else if (e.code == 'weak-password') {
        message = "Password is too weak";
      } else {
        message = e.message ?? "Signup failed";
      }
      _showSnack(message, color: const Color(0xFFE63946));
    } catch (e) {
      _showSnack("Error: ${e.toString()}", color: Colors.orange);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _showSnack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C2E),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                // 🔴 Icon
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: accentRed,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.security,
                      color: Colors.white, size: 32),
                ),

                const SizedBox(height: 16),

                const Text(
                  "Create Account",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                const Text(
                  "Your messages will be secured automatically",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),

                const SizedBox(height: 24),

                // Name
                _buildField(
                  nameController,
                  "Full Name",
                  Icons.person,
                ),
                const SizedBox(height: 12),

                // Email
                _buildField(
                  emailController,
                  "Email",
                  Icons.email,
                  isEmail: true,
                ),
                const SizedBox(height: 12),

                // Mobile number
                _buildField(
                  phoneController,
                  "Mobile Number",
                  Icons.phone,
                  isPhone: true,
                ),
                const SizedBox(height: 12),

                // Password
                _buildPasswordField(
                  passwordController,
                  "Password",
                  obscurePassword,
                  () => setState(
                      () => obscurePassword = !obscurePassword),
                ),
                const SizedBox(height: 12),

                // Confirm Password
                _buildPasswordField(
                  confirmPasswordController,
                  "Confirm Password",
                  obscureConfirm,
                  () => setState(
                      () => obscureConfirm = !obscureConfirm),
                ),

                const SizedBox(height: 24),

                // ✅ Security Number Picker
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: accentRed.withOpacity(0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Row(
                        children: [
                          const Icon(Icons.lock,
                              color: Colors.green, size: 18),
                          const SizedBox(width: 8),
                          const Text(
                            "Choose Your Security Number",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),

                      const Text(
                        "Pick any number to secure your account.\nEach number uses a different hidden encryption.",
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ✅ Number grid 1-10
                      GridView.builder(
                        shrinkWrap: true,
                        physics:
                            const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1,
                        ),
                        itemCount: 10,
                        itemBuilder: (context, index) {
                          final number = index + 1;
                          final isSelected =
                              selectedNumber == number;

                          return GestureDetector(
                            onTap: () => setState(
                                () => selectedNumber = number),
                            child: AnimatedContainer(
                              duration:
                                  const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? accentRed
                                    : const Color(0xFF2C2C2E),
                                borderRadius:
                                    BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? accentRed
                                      : Colors.white12,
                                  width: isSelected ? 2 : 1,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: accentRed
                                              .withOpacity(0.4),
                                          blurRadius: 8,
                                          spreadRadius: 1,
                                        )
                                      ]
                                    : [],
                              ),
                              child: Center(
                                child: Text(
                                  "$number",
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white54,
                                    fontSize: 20,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 14),

                      // ✅ Selected number display
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.green.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle,
                                color: Colors.green, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              "Security Algorithm $selectedNumber selected",
                              style: const TextStyle(
                                color: Colors.green,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ✅ Sign Up Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentRed,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: loading ? null : signUp,
                    child: loading
                        ? const CircularProgressIndicator(
                            color: Colors.white)
                        : Text(
                            "Create Secure Account  🔐",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 12),

                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Already have an account? Login",
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String hint,
    IconData icon, {
    bool isEmail = false,
    bool isPhone = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType:
          isEmail
              ? TextInputType.emailAddress
              : isPhone
                  ? TextInputType.phone
                  : TextInputType.text,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.white54),
        filled: true,
        fillColor: const Color(0xFF3A3A3C),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildPasswordField(
    TextEditingController controller,
    String hint,
    bool obscure,
    VoidCallback onToggle,
  ) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: const Icon(Icons.lock, color: Colors.white54),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off : Icons.visibility,
            color: Colors.white54,
          ),
          onPressed: onToggle,
        ),
        filled: true,
        fillColor: const Color(0xFF3A3A3C),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}