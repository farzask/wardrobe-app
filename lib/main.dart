import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/config/app_config.dart';
import 'core/services/backend_api_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/image_capture_service.dart';
import 'core/services/local_cache.dart';
import 'core/services/supabase_service.dart';
import 'core/services/thumbnail_resolver.dart';
import 'core/theme/app_spacing.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/viewmodels/auth_viewmodel.dart';
import 'features/auth/views/sign_in_view.dart';
import 'features/onboarding/views/onboarding_view.dart';
import 'features/outfit/viewmodels/outfit_viewmodel.dart';
import 'features/wardrobe/viewmodels/add_item_viewmodel.dart';
import 'features/wardrobe/viewmodels/wardrobe_viewmodel.dart';
import 'features/wardrobe/views/wardrobe_home_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A build with no credentials fails here, with a message naming what is missing — rather than
  // with a null-check crash three screens in.
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
    return MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.key_off_outlined, size: 40),
                const SizedBox(height: AppSpacing.md),
                Builder(
                  builder: (context) => Text(
                    'FitCheck is not configured',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Builder(
                  builder: (context) => Text(
                    'Missing: ${AppConfig.missingKeys.join(', ')}.\n\n'
                    'Pass them with --dart-define. See supabase/SETUP.md.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
