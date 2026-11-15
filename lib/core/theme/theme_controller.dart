import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'app_theme_mode';

/// Persisted light/dark preference. Kept in SharedPreferences so the choice
/// survives restarts without adding a Firestore dependency. Only light and
/// dark modes are supported; any legacy "system" value is migrated to light.
class ThemeController extends StateNotifier<ThemeMode> {
  ThemeController() : super(ThemeMode.light) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      final mode = switch (stored) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        'system' => ThemeMode.light,
        _ => ThemeMode.light,
      };
      if (mounted) state = mode;
      if (stored == 'system') {
        await prefs.setString(_prefsKey, 'light');
      }
    } catch (_) {
      // Preference storage is optional; default to light.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    final resolved =
        mode == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light;
    state = resolved;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        resolved == ThemeMode.dark ? 'dark' : 'light',
      );
    } catch (_) {
      // Keep the in-memory choice even if persistence fails.
    }
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeController, ThemeMode>((_) => ThemeController());
