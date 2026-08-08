import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Runtime configuration, resolved from two sources with `--dart-define` taking precedence.
///
/// ```
/// flutter run                                   # reads .env at the project root
/// flutter build apk --dart-define=BACKEND_URL=… # overrides .env, for CI and release
/// ```
///
/// Why both: `.env` is the convenience path so day-to-day `flutter run` needs no arguments, and
/// `--dart-define` stays available because CI does not have a `.env` file and release builds should
/// take their values from the build system rather than from a developer's untracked file.
/// `--dart-define` wins on any key it supplies, so a release build can never accidentally pick up
/// a local `.env`.
///
/// ## What may go in `.env` — and what must not
///
/// **`flutter_dotenv` bundles `.env` as a Flutter asset.** The file ships inside the APK/IPA and
/// anyone can extract it. It is a convenience, **not** a secret store.
///
/// Only these three belong there, and all three are safe to ship:
///
/// - `SUPABASE_URL` — public.
/// - `SUPABASE_ANON_KEY` — public by design. Grants nothing on its own; every table is protected
///   by the RLS policies in migrations 002–007.
/// - `BACKEND_URL` — public.
///
/// **Never in this file:** `SUPABASE_SERVICE_ROLE_KEY` (bypasses every RLS policy) or
/// `SUPABASE_JWT_SECRET` (lets the holder mint a valid token for any user). Those live in
/// `backend/.env` and are read only by the Python service.
///
/// To be clear about what this does and does not buy: `--dart-define` values are also recoverable
/// from a compiled binary, so neither mechanism hides anything. The reason to keep server secrets
/// out is that they are genuinely dangerous, not that assets are uniquely leaky.
abstract final class AppConfig {
  const AppConfig._();

  // Compile-time overrides. Empty string when the define was not passed.
  static const String _defineUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _defineAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String _defineBackendUrl = String.fromEnvironment('BACKEND_URL');

  /// Load `.env`. Safe to call when the file is absent — [isConfigured] then reports what is
  /// missing instead of the app crashing on launch.
  static Future<void> load() async {
    await dotenv.load(isOptional: true);
  }

  static String _read(String defineValue, String key) {
    if (defineValue.isNotEmpty) return defineValue;
    // `dotenv.env` throws when load() has not run — which is the normal case in unit tests, where
    // nothing should need configuration at all.
    if (!dotenv.isInitialized) return '';
    return dotenv.env[key]?.trim() ?? '';
  }

  static String get supabaseUrl => _read(_defineUrl, 'SUPABASE_URL');
  static String get supabaseAnonKey => _read(_defineAnonKey, 'SUPABASE_ANON_KEY');
  static String get backendUrl => _read(_defineBackendUrl, 'BACKEND_URL');

  static bool get isConfigured => missingKeys.isEmpty;

  /// Named so a misconfigured build fails with a message that says what to do, rather than with a
  /// null-check crash three screens in.
  static List<String> get missingKeys => <String>[
        if (supabaseUrl.isEmpty) 'SUPABASE_URL',
        if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
        if (backendUrl.isEmpty) 'BACKEND_URL',
      ];

  /// True when `.env` was found and parsed. Used only to tell the user *why* configuration is
  /// missing — "no .env file" and "`.env` exists but has no BACKEND_URL" need different fixes.
  static bool get envFileLoaded => dotenv.isInitialized && dotenv.env.isNotEmpty;

  /// Where each value actually came from.
  ///
  /// Worth its keep: when configuration looks wrong, the useful question is almost never "what is
  /// the value" but "which source won". A key present in `.env` yet reported missing means the
  /// build is stale — `.env` is an *asset*, so adding it to `pubspec.yaml` needs a full
  /// stop-and-rerun, and neither hot reload nor hot restart will pick it up.
  static Map<String, String> get sources => <String, String>{
        'SUPABASE_URL': _sourceOf(_defineUrl, 'SUPABASE_URL'),
        'SUPABASE_ANON_KEY': _sourceOf(_defineAnonKey, 'SUPABASE_ANON_KEY'),
        'BACKEND_URL': _sourceOf(_defineBackendUrl, 'BACKEND_URL'),
      };

  static String _sourceOf(String defineValue, String key) {
    if (defineValue.isNotEmpty) return '--dart-define';
    if (!dotenv.isInitialized) return 'not set (.env never loaded)';
    final fromFile = dotenv.env[key]?.trim() ?? '';
    if (fromFile.isNotEmpty) return '.env';
    return dotenv.env.containsKey(key) ? '.env, but empty' : 'not set';
  }

  /// Refuse to run if a server secret has been pasted into the client `.env`.
  ///
  /// This is the failure this whole split exists to prevent, and it is an easy mistake: the two
  /// files have the same name and similar contents. Rather than trusting the documentation to be
  /// read, the app checks — a build carrying these keys must not reach a phone.
  static List<String> get leakedServerSecrets => <String>[
        if (dotenv.isInitialized) ...[
          if ((dotenv.env['SUPABASE_SERVICE_ROLE_KEY'] ?? '').isNotEmpty)
            'SUPABASE_SERVICE_ROLE_KEY',
          if ((dotenv.env['SUPABASE_JWT_SECRET'] ?? '').isNotEmpty)
            'SUPABASE_JWT_SECRET',
          if ((dotenv.env['GEMINI_API_KEY'] ?? '').isNotEmpty) 'GEMINI_API_KEY',
        ],
      ];
}
