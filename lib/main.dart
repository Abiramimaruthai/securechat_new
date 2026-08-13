import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'firebase_options.dart';
import 'home_page.dart';
import 'lock_screen.dart';
import 'login_page.dart';
import 'notification_service.dart';
import 'signup_page.dart';
import 'supabase_config.dart';
import 'verify_email_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.isDarkMode,
      builder: (context, isDark, _) {
        return MaterialApp(
          navigatorKey: NotificationService.navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'SecureChat',
          theme: AppThemes.lightTheme,
          darkTheme: AppThemes.darkTheme,
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          home: const AppBootstrap(),
          routes: {
            '/login': (context) => const LoginPage(),
            '/signup': (context) => const SignupPage(),
            '/home': (context) => const HomeRouteGate(),
            '/verify-email': (context) => const VerifyEmailPage(),
          },
        );
      },
    );
  }
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late final Future<void> _bootstrapFuture = _bootstrap();

  Future<void> _bootstrap() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await SupabaseConfig.initializeIfConfigured();
    await AppSettings.load();
    await AppSettings.applyScreenshotPreference();
    unawaited(NotificationService.initialize());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SplashLoader();
        }

        if (snapshot.hasError) {
          return const SplashLoader();
        }

        return const StartupGate();
      },
    );
  }
}

class StartupGate extends StatelessWidget {
  const StartupGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.appLockEnabled,
      builder: (context, appLockEnabled, _) {
        if (appLockEnabled) {
          return const LockScreen();
        }
        return const AuthWrapper();
      },
    );
  }
}

class HomeRouteGate extends StatelessWidget {
  const HomeRouteGate({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const LoginPage();
    if (user.emailVerified != true) {
      return VerifyEmailPage(email: user.email ?? '');
    }
    return const HomePage();
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      // `userChanges()` reacts to `reload()` updates (like emailVerified flips).
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashLoader();
        }

        if (snapshot.hasData) {
          final user = snapshot.data!;
          if (user.emailVerified != true) {
            return VerifyEmailPage(email: user.email ?? '');
          }
          return const HomePage();
        }

        return const LoginPage();
      },
    );
  }
}

class SplashLoader extends StatelessWidget {
  const SplashLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: const SizedBox.expand(),
    );
  }
}

class AppThemes {
  static const darkScaffold = Color(0xFF1A1A1A);
  static const darkSurface = Color(0xFF2C2C2E);
  static const accent = Color(0xFFE63946);
  static const lightScaffold = Color(0xFFF6F7FB);
  static const lightSurface = Colors.white;

  static ThemeData get darkTheme {
    const scheme = ColorScheme.dark(
      primary: accent,
      secondary: accent,
      surface: darkSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkScaffold,
      colorScheme: scheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardColor: darkSurface,
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? accent
              : Colors.grey.shade400;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? accent.withOpacity(0.45)
              : Colors.white24;
        }),
      ),
    );
  }

  static ThemeData get lightTheme {
    const scheme = ColorScheme.light(
      primary: accent,
      secondary: accent,
      surface: lightSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightScaffold,
      colorScheme: scheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: lightSurface,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      cardColor: lightSurface,
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? accent
              : Colors.grey.shade500;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? accent.withOpacity(0.35)
              : Colors.black12;
        }),
      ),
    );
  }
}
