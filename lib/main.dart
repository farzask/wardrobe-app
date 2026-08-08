import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/config/app_config.dart';
import 'core/services/backend_api_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/image_capture_service.dart';
import 'core/services/local_cache.dart';
import 'core/services/supabase_service.dart';
import 'core/services/thumbnail_resolver.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_spacing.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_typography.dart';
import 'features/auth/viewmodels/auth_viewmodel.dart';
import 'features/auth/views/sign_in_view.dart';
import 'features/onboarding/views/onboarding_view.dart';
import 'features/outfit/viewmodels/outfit_viewmodel.dart';
import 'features/wardrobe/viewmodels/add_item_viewmodel.dart';
import 'features/wardrobe/viewmodels/wardrobe_viewmodel.dart';
import 'features/wardrobe/views/wardrobe_home_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Reads `.env` at the project root. Absent is not fatal — `--dart-define` may be supplying the
  // values instead, and if neither does, the screen below says exactly what is missing.
  await AppConfig.load();

  // Hard stop, before anything else. `.env` is bundled as an app asset, so a server secret pasted
  // into it ships to every phone — and SUPABASE_JWT_SECRET in particular lets the holder mint a
  // valid token for any user. Refusing to launch is the only response proportionate to that.
  if (AppConfig.leakedServerSecrets.isNotEmpty) {
    runApp(const _LeakedSecretsApp());
    return;
  }

  if (!AppConfig.isConfigured) {
    runApp(const _MisconfiguredApp());
    return;
  }

  final supabase = await SupabaseService.initialize();
  final cache = await LocalCache.open();

  runApp(FitCheckApp(supabase: supabase, cache: cache));
}

class FitCheckApp extends StatelessWidget {
  const FitCheckApp({super.key, required this.supabase, required this.cache});

  final SupabaseService supabase;
  final LocalCache cache;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: supabase),
        Provider.value(value: cache),
        Provider(create: (_) => ConnectivityService()),
        Provider(create: (_) => ImageCaptureService()),
        Provider(
          create: (_) => BackendApiService(tokenProvider: () => supabase.accessToken),
          dispose: (_, BackendApiService service) => service.dispose(),
        ),
        ChangeNotifierProvider(create: (_) => ThumbnailResolver(supabase)),
        ChangeNotifierProvider(
          create: (_) => AuthViewModel(supabase: supabase, cache: cache),
        ),
      ],
      child: MaterialApp(
        title: 'FitCheck',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: const _Router(),
      ),
    );
  }
}

/// Routes on auth + onboarding state.
///
/// One switch over [AuthStage] rather than a set of nested conditionals, so "signed in but
/// mid-onboarding" resolves to exactly one destination and cannot fall between cases.
class _Router extends StatelessWidget {
  const _Router();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();

    return switch (auth.stage) {
      AuthStage.resolving => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      AuthStage.signedOut => const SignInView(),
      AuthStage.needsGender => const GenderSelectView(),
      AuthStage.needsAccessoryAnswer => const AccessoryOptInView(),
      AuthStage.ready => _SignedIn(userId: auth.userId!),
    };
  }
}

/// Per-user scopes live below the router so they are rebuilt from scratch on sign-out and cannot
/// leak one account's wardrobe into the next session.
class _SignedIn extends StatelessWidget {
  const _SignedIn({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      // Keyed by user id: signing in as someone else replaces these rather than reusing them.
      key: ValueKey(userId),
      providers: [
        ChangeNotifierProvider(
          create: (context) => WardrobeViewModel(
            supabase: context.read<SupabaseService>(),
            cache: context.read<LocalCache>(),
            connectivity: context.read<ConnectivityService>(),
            userId: userId,
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => AddItemViewModel(
            backend: context.read<BackendApiService>(),
            supabase: context.read<SupabaseService>(),
            capture: context.read<ImageCaptureService>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => OutfitViewModel(
            backend: context.read<BackendApiService>(),
            connectivity: context.read<ConnectivityService>(),
          ),
        ),
      ],
      child: const WardrobeHomeView(),
    );
  }
}

class _MisconfiguredApp extends StatelessWidget {
  const _MisconfiguredApp();

  @override
  Widget build(BuildContext context) {
    // Show where every value resolved from, not just which ones are missing. "BACKEND_URL — not
    // set (.env never loaded)" tells you the build is stale; "BACKEND_URL — .env, but empty" tells
    // you to edit the file. The bare list of missing keys cannot distinguish those, and they have
    // completely different fixes.
    final report =
        AppConfig.sources.entries.map((e) => '${e.key}  →  ${e.value}').join('\n');

    final fix = AppConfig.envFileLoaded
        ? 'Fill in the missing keys in .env at the project root.'
        : '.env was not loaded.\n\n'
            'If the file exists and has these keys, the running build is stale: .env is a '
            'Flutter ASSET, so hot reload and hot restart cannot pick it up. Fully stop the app '
            'and run it again:\n\n'
            '    flutter clean && flutter pub get && flutter run\n\n'
            'If the file does not exist, copy .env.example to .env.';

    return _StartupMessage(
      icon: Icons.key_off_outlined,
      title: 'FitCheck is not configured',
      detail: '$report\n\n$fix\n\nSee supabase/SETUP.md §2.',
      monospaceDetail: true,
    );
  }
}

/// Shown instead of the app when `.env` contains a key that must never reach a phone.
class _LeakedSecretsApp extends StatelessWidget {
  const _LeakedSecretsApp();

  @override
  Widget build(BuildContext context) {
    return _StartupMessage(
      icon: Icons.gpp_bad_outlined,
      title: 'Server secrets in the app .env',
      detail: 'Found: ${AppConfig.leakedServerSecrets.join(', ')}.\n\n'
          '.env is bundled into the app and can be extracted from the build, so these would be '
          'readable by anyone who installs it. SUPABASE_JWT_SECRET in particular lets the holder '
          'sign a token for any account.\n\n'
          'Move them to backend/.env, which is only read by the Python service. The app needs '
          'just SUPABASE_URL, SUPABASE_ANON_KEY and BACKEND_URL.',
      isDanger: true,
    );
  }
}

/// Shared shell for the two pre-launch failure screens. Both happen before any provider exists, so
/// neither can use the normal app scaffolding.
class _StartupMessage extends StatelessWidget {
  const _StartupMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.isDanger = false,
    this.monospaceDetail = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool isDanger;

  /// Set for the configuration report, where the values line up in columns and a proportional face
  /// would make them unreadable.
  final bool monospaceDetail;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: Builder(
        builder: (context) {
          final palette = AppColors.of(context);
          return Scaffold(
            body: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 40,
                        color: isDanger ? palette.danger : palette.onSurfaceMuted,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: isDanger ? palette.danger : palette.onSurface,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        detail,
                        textAlign:
                            monospaceDetail ? TextAlign.left : TextAlign.center,
                        style: monospaceDetail
                            ? AppTypography.monoValue(palette.onSurfaceMuted, size: 12)
                            : Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
