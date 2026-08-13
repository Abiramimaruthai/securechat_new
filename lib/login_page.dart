import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'verify_email_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final Color bg = const Color(0xFF1A1A1A);
  final Color card = const Color(0xFF2C2C2E);
  final Color accent = const Color(0xFFE63946);

  bool loading = false;
  bool obscurePassword = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Widget buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: isPassword
          ? TextInputType.text
          : TextInputType.emailAddress,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFF3A3A3C),
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
        prefixIcon: Icon(icon, color: Colors.white54),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white54,
                ),
                onPressed: () {
                  setState(() => obscurePassword = !obscurePassword);
                },
              )
            : null,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Future<void> login() async {
    // ✅ Validate inputs
    if (emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your email")),
      );
      return;
    }

    if (passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your password")),
      );
      return;
    }

    setState(() => loading = true);

    try {
      // ✅ Sign in with Firebase
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      await credential.user?.reload();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.emailVerified != true) {
        String? verificationSendError;
        try {
          await user.sendEmailVerification();
        } on FirebaseAuthException catch (e) {
          verificationSendError = e.message ?? e.code;
        } catch (e) {
          verificationSendError = e.toString();
        }
        if (mounted) {
          if (verificationSendError != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text("Couldn't send verification email: $verificationSendError"),
                backgroundColor: const Color(0xFFE63946),
              ),
            );
          }
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => VerifyEmailPage(
                email: user.email ?? emailController.text.trim(),
              ),
            ),
          );
        }
        return;
      }

      // ✅ Navigate to HomePage
      Navigator.pushReplacementNamed(context, '/home');

    } on FirebaseAuthException catch (e) {
      String message = "Login failed";

      // ✅ Friendly error messages
      if (e.code == 'user-not-found') {
        message = "No account found with this email";
      } else if (e.code == 'wrong-password') {
        message = "Incorrect password";
      } else if (e.code == 'invalid-email') {
        message = "Invalid email address";
      } else if (e.code == 'user-disabled') {
        message = "This account has been disabled";
      } else if (e.code == 'too-many-requests') {
        message = "Too many attempts. Try again later";
      } else {
        message = e.message ?? "Login failed";
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFFE63946),
        ),
      );
    }

    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  // 🔴 App Icon
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),

                  const SizedBox(height: 16),

                  const Text(
                    "SecureChat",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 6),

                  const Text(
                    "Login to your account",
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Email Field
                  buildField(
                    controller: emailController,
                    hint: "Email",
                    icon: Icons.email,
                    obscure: false,
                  ),

                  const SizedBox(height: 12),

                  // Password Field
                  buildField(
                    controller: passwordController,
                    hint: "Password",
                    icon: Icons.lock,
                    obscure: obscurePassword,
                    isPassword: true,
                  ),

                  const SizedBox(height: 8),

                  // Forgot Password
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () async {
                        if (emailController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Enter your email first"),
                            ),
                          );
                          return;
                        }
                        await FirebaseAuth.instance.sendPasswordResetEmail(
                          email: emailController.text.trim(),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Password reset email sent!"),
                          ),
                        );
                      },
                      child: const Text(
                        "Forgot Password?",
                        style: TextStyle(color: Color(0xFFE63946)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Login Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: loading ? null : login,
                      child: loading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              "Login",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Sign Up Link
                  TextButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/signup');
                    },
                    child: const Text(
                      "Don't have an account? Sign Up",
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}