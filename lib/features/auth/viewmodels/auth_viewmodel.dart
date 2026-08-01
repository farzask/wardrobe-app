import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../../core/services/local_cache.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/vocabulary/fc_vocabulary.dart';
import '../models/profile.dart';

/// Where the app should be, derived from auth + profile state.
///
/// Modelled as one enum rather than a set of booleans so that "signed in but mid-onboarding" cannot
/// be represented ambiguously — the router reads exactly one value.
enum AuthStage { resolving, signedOut, needsGender, needsAccessoryAnswer, ready }

class AuthViewModel extends ChangeNotifier {
  AuthViewModel({required SupabaseService supabase, required LocalCache cache})
      : _supabase = supabase,
        _cache = cache {
    _subscription = _supabase.authStateChanges.listen((_) => _resolve());
    _resolve();
  }

  final SupabaseService _supabase;
  final LocalCache _cache;
  StreamSubscription<dynamic>? _subscription;

  AuthStage _stage = AuthStage.resolving;
  Profile? _profile;
  String? _errorMessage;
  bool _busy = false;

  AuthStage get stage => _stage;
  Profile? get profile => _profile;
  String? get errorMessage => _errorMessage;
  bool get busy => _busy;
  String? get userId => _supabase.currentUserId;

  Future<void> _resolve() async {
    final id = _supabase.currentUserId;
    if (id == null) {
      _profile = null;
      _set(AuthStage.signedOut);
      return;
    }

    // The profile row is created by a database trigger on signup. Immediately after signUp() the
    // trigger has occasionally not committed yet, so a single miss is retried rather than being
    // shown to the user as a broken account.
    var profile = await _supabase.fetchProfile(id);
    if (profile == null) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      profile = await _supabase.fetchProfile(id);
    }

    _profile = profile;
    if (profile == null || profile.gender == null) {
      _set(AuthStage.needsGender);
    } else if (!profile.isOnboardingComplete) {
      _set(AuthStage.needsAccessoryAnswer);
    } else {
      _set(AuthStage.ready);
    }
  }

  Future<bool> signUp({required String email, required String password}) =>
      _run(() => _supabase.signUp(email: email, password: password));

  Future<bool> signIn({required String email, required String password}) =>
      _run(() => _supabase.signIn(email: email, password: password));

  Future<bool> chooseGender(FcGender gender) => _run(() async {
        _profile = await _supabase.setGender(userId!, gender);
      });

  Future<bool> answerAccessories(bool wearsAccessories) => _run(() async {
        _profile = await _supabase.setWearsAccessories(userId!, wearsAccessories);
      });

  Future<void> signOut() async {
    // Clear the cache before signing out. Leaving one person's wardrobe on the device for whoever
    // signs in next would undo the isolation that TRD §9's RLS policies exist to provide.
    await _cache.clear();
    await _supabase.signOut();
  }

  Future<bool> _run(Future<void> Function() action) async {
    _busy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await action();
      await _resolve();
      return true;
    } on AuthException catch (e) {
      // Supabase's own message is the useful one here ("Invalid login credentials"); replacing it
      // with something generic would make a wrong password indistinguishable from an outage.
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Something went wrong. Check your connection and try again.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _set(AuthStage stage) {
    _stage = stage;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
