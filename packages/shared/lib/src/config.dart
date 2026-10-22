import 'package:shared_preferences/shared_preferences.dart';

/// Supabase configuration manager for Family Guard.
///
/// Pre-configured with the user's Supabase project credentials.
/// Can also be overridden dynamically via:
/// 1. Passing `--dart-define=SUPABASE_URL=...` and `--dart-define=SUPABASE_ANON_KEY=...` (or `SUPABASE_PUBLISHABLE_KEY=...`).
/// 2. In-app Supabase Connection Settings dialog (saved to SharedPreferences).
class SupabaseConfig {
  static const String defaultUrl = 'https://hogchyavwafcuyxahhvb.supabase.co';
  static const String defaultAnonKey =
      'sb_publishable_PJCgdrbrQ7dYiTMT4W7R1A_oHOo4yHL';
  static const String authCallbackUrl =
      'io.supabase.familyguard://login-callback/';

  static const String _prefUrlKey = 'fg_custom_supabase_url';
  static const String _prefAnonKey = 'fg_custom_supabase_anon_key';

  static String _activeUrl = '';
  static String _activeAnonKey = '';
  static bool _initialized = false;

  /// Loads stored configuration from SharedPreferences or environment
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customUrl = prefs.getString(_prefUrlKey);
      final customKey = prefs.getString(_prefAnonKey);

      const envUrl = String.fromEnvironment('SUPABASE_URL');
      const envKey = String.fromEnvironment(
        'SUPABASE_ANON_KEY',
        defaultValue: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
      );

      if (customUrl != null && customUrl.trim().isNotEmpty) {
        _activeUrl = customUrl.trim();
      } else if (envUrl.isNotEmpty) {
        _activeUrl = envUrl.trim();
      } else {
        _activeUrl = defaultUrl;
      }

      if (customKey != null && customKey.trim().isNotEmpty) {
        _activeAnonKey = customKey.trim();
      } else if (envKey.isNotEmpty) {
        _activeAnonKey = envKey.trim();
      } else {
        _activeAnonKey = defaultAnonKey;
      }
    } catch (_) {
      _activeUrl = defaultUrl;
      _activeAnonKey = defaultAnonKey;
    } finally {
      _initialized = true;
    }
  }

  /// Current active Supabase URL
  static String get url {
    if (!_initialized || _activeUrl.isEmpty) {
      const envUrl = String.fromEnvironment('SUPABASE_URL');
      return envUrl.isNotEmpty ? envUrl : defaultUrl;
    }
    return _activeUrl;
  }

  /// Current active Supabase Publishable / Anon Key
  static String get anonKey {
    if (!_initialized || _activeAnonKey.isEmpty) {
      const envKey = String.fromEnvironment(
        'SUPABASE_ANON_KEY',
        defaultValue: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
      );
      return envKey.isNotEmpty ? envKey : defaultAnonKey;
    }
    return _activeAnonKey;
  }

  /// Checks if real (non-dummy) Supabase credentials have been configured
  static bool get isRealSupabaseConfigured {
    final u = url.toLowerCase().trim();
    final k = anonKey.toLowerCase().trim();

    if (u.contains('your_project') ||
        u.contains('dummy') ||
        u.contains('example.com') ||
        !u.startsWith('http')) {
      return false;
    }

    if (k.contains('your_anon_key') ||
        k.contains('dummy') ||
        k.contains('placeholder') ||
        k.length < 20) {
      return false;
    }

    return true;
  }

  /// Kept for backward compatibility
  static bool get isConfigured => true;

  /// Save new Supabase credentials entered from the app UI
  static Future<void> saveCustomConfig(String newUrl, String newKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefUrlKey, newUrl.trim());
    await prefs.setString(_prefAnonKey, newKey.trim());
    _activeUrl = newUrl.trim();
    _activeAnonKey = newKey.trim();
  }

  /// Reset credentials back to project defaults
  static Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefUrlKey);
    await prefs.remove(_prefAnonKey);
    _activeUrl = defaultUrl;
    _activeAnonKey = defaultAnonKey;
  }
}

/// Fallback demo credentials for local testing mode
class DemoCredentials {
  static const String password = '1234';
  static const String pairCode = '1234';
  static const String familyId = 'local-family-1';
  static const String parentId = 'local-parent-1';
  static const String childId = 'local-child-1';
}
