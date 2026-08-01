/// Build-time configuration.
///
/// Supplied via `--dart-define` so no credential is ever committed:
///
/// ```
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJ... \
///   --dart-define=BACKEND_URL=https://fitcheck-backend.up.railway.app
/// ```
///
/// The anon key is public by design and safe to ship in the app: every table is protected by the
/// RLS policies in migrations 002–007, so the key alone grants access to nothing. The
/// service-role key is a different matter and must never appear in this file, this package, or any
/// build — it bypasses every one of those policies.
abstract final class AppConfig {
  const AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String backendUrl = String.fromEnvironment('BACKEND_URL');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty && backendUrl.isNotEmpty;

  /// Named so a misconfigured build fails with a message that says what to do, rather than with a
  /// null-check crash three screens in.
  static List<String> get missingKeys => <String>[
        if (supabaseUrl.isEmpty) 'SUPABASE_URL',
        if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
        if (backendUrl.isEmpty) 'BACKEND_URL',
      ];
}
