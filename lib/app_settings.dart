import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  static const _platform = MethodChannel('securechat/security');

  static final ValueNotifier<bool> isDarkMode = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> appLockEnabled = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> screenshotAllowed =
      ValueNotifier<bool>(false);
  static final ValueNotifier<bool> selfDestructEnabled =
      ValueNotifier<bool>(false);
  static final ValueNotifier<int> selfDestructSeconds = ValueNotifier<int>(0);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    isDarkMode.value = prefs.getBool('darkTheme') ?? true;
    appLockEnabled.value = prefs.getBool('appLock') ?? false;
    screenshotAllowed.value = prefs.getBool('screenshotAllowed') ?? false;
    selfDestructEnabled.value = prefs.getBool('selfDestructEnabled') ?? false;
    selfDestructSeconds.value = prefs.getInt('selfDestructSeconds') ?? 30;
  }

  static Future<void> setDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkTheme', value);
    isDarkMode.value = value;
  }

  static Future<void> setAppLock(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('appLock', value);
    appLockEnabled.value = value;
  }

  static Future<void> setScreenshotAllowed(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('screenshotAllowed', value);
    screenshotAllowed.value = value;
    await applyScreenshotPreference();
  }

  static Future<void> setSelfDestructEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('selfDestructEnabled', value);
    selfDestructEnabled.value = value;
  }

  static Future<void> setSelfDestructSeconds(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('selfDestructSeconds', seconds);
    selfDestructSeconds.value = seconds;
  }

  static Future<void> applyScreenshotPreference() async {
    try {
      await _platform.invokeMethod<void>(
        'setScreenshotAllowed',
        screenshotAllowed.value,
      );
    } catch (_) {
      // Ignored on unsupported platforms.
    }
  }
}
