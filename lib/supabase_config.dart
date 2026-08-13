import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  SupabaseConfig._();

  static bool _initialized = false;
  static bool get initialized => _initialized;

  // Configure these at build/run time:
  // flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static Future<void> initializeIfConfigured() async {
    if (_initialized) return;
    if (url.isEmpty || anonKey.isEmpty) return;
    await Supabase.initialize(url: url, anonKey: anonKey);
    _initialized = true;
  }
}

