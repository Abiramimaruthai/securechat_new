import 'dart:typed_data';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

class SupabaseMediaService {
  SupabaseMediaService._();

  static const String _bucket = 'securechat-media';

  static Exception _mapNetworkError(Object e) {
    // SocketException messages differ across devices/Android versions.
    final msg = e.toString();
    if (e is SocketException ||
        msg.contains('Failed host lookup') ||
        msg.contains('No address associated with hostname') ||
        msg.contains('Network is unreachable')) {
      return Exception(
        'Network/DNS error: cannot reach Supabase. '
        'Check that your phone has internet access, disable VPN/ad-block DNS if any, '
        'and verify SUPABASE_URL is correct (e.g. https://<project-ref>.supabase.co). '
        'Original: $msg',
      );
    }
    return Exception(msg);
  }

  static Future<Map<String, String>> uploadMedia({
    required String chatId,
    required String type,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (!SupabaseConfig.initialized) {
      throw Exception(
        'Supabase not configured. Run/build with --dart-define=SUPABASE_URL=... and --dart-define=SUPABASE_ANON_KEY=...',
      );
    }
    final folder = switch (type) {
      'image' => 'images',
      'video' => 'videos',
      'voice' => 'voice',
      _ => 'files',
    };

    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath =
        '$folder/$chatId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    final contentType = switch (type) {
      'image' => 'image/jpeg',
      'video' => 'video/mp4',
      'voice' => 'audio/mp4',
      _ => 'application/octet-stream',
    };

    final client = Supabase.instance.client;
    try {
      await client.storage.from(_bucket).uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: contentType,
            ),
          );

      final mediaUrl = await client.storage
          .from(_bucket)
          .createSignedUrl(storagePath, 60 * 60 * 24 * 7);

      return {
        'mediaUrl': mediaUrl,
        'storagePath': storagePath,
      };
    } catch (e) {
      throw _mapNetworkError(e);
    }
  }

  static Future<String> refreshSignedUrl(
    String storagePath, {
    int expiresInSeconds = 60 * 60 * 24 * 7,
  }) {
    if (!SupabaseConfig.initialized) {
      throw Exception(
        'Supabase not configured. Cannot refresh media URLs.',
      );
    }
    final client = Supabase.instance.client;
    return client.storage
        .from(_bucket)
        .createSignedUrl(storagePath, expiresInSeconds)
        .catchError((e) => throw _mapNetworkError(e));
  }
}
