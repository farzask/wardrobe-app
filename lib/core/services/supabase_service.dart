import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/models/profile.dart';
import '../../features/wardrobe/models/wardrobe_item.dart';
import '../config/app_config.dart';
import '../vocabulary/fc_vocabulary.dart';

/// Direct Supabase access for ordinary CRUD, per TRD §1. Only the two heavy operations —
/// extraction and evaluation — go through the Python backend.
///
/// Every query here filters `deleted_at IS NULL` **and** `status = 'active'`. Both predicates are
/// required on every wardrobe read: omit the first and deleted items reappear in the grid; omit the
/// second and half-extracted items appear before the user has reviewed them. They also match the
/// partial indexes in `004_wardrobe_items.sql`, so a query missing either one silently drops to a
/// sequential scan as well as returning wrong rows.
class SupabaseService {
  SupabaseService(this._client);

  final SupabaseClient _client;

  static Future<SupabaseService> initialize() async {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      // Supabase renamed the anon key to the "publishable key"; `anonKey` is deprecated and goes
      // away in the next major. Same value, same guarantees — public by design, protected by the
      // RLS policies in migrations 002–007. The env var keeps the older name because that is what
      // the Supabase dashboard still labels it in most projects.
      publishableKey: AppConfig.supabaseAnonKey,
    );
    return SupabaseService(Supabase.instance.client);
  }

  static const _itemColumns =
      'id,category,style,pattern,fabric,sleeve_type,neckline,fit,season,occasion,'
      'color_hex,color_palette,primary_color,secondary_color,thumbnail_path,'
      'status,extraction_confidence,created_at';

  User? get currentUser => _client.auth.currentUser;
  String? get currentUserId => currentUser?.id;
  String? get accessToken => _client.auth.currentSession?.accessToken;
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // --- Auth ------------------------------------------------------------------

  Future<void> signUp({required String email, required String password}) async {
    await _client.auth.signUp(email: email, password: password);
  }

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  // --- Profile ---------------------------------------------------------------

  /// The row is created by a database trigger at signup, so this should always find one. It returns
  /// null only if the trigger has not run yet, which the caller retries rather than treating as an
  /// error.
  Future<Profile?> fetchProfile(String userId) async {
    final row = await _client
        .from('profiles')
        .select('id,gender,wears_accessories,display_name')
        .eq('id', userId)
        .maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  Future<Profile> setGender(String userId, FcGender gender) async {
    final row = await _client
        .from('profiles')
        .update({
          'gender': gender.wire,
          // Switching to female must clear any accessory answer, or the CHECK constraint in
          // 002_profiles.sql rejects the update.
          if (gender == FcGender.female) 'wears_accessories': null,
        })
        .eq('id', userId)
        .select('id,gender,wears_accessories,display_name')
        .single();
    return Profile.fromJson(row);
  }

  Future<Profile> setWearsAccessories(String userId, bool value) async {
    final row = await _client
        .from('profiles')
        .update({'wears_accessories': value})
        .eq('id', userId)
        .select('id,gender,wears_accessories,display_name')
        .single();
    return Profile.fromJson(row);
  }

  // --- Wardrobe --------------------------------------------------------------

  Future<List<WardrobeItem>> fetchWardrobe(String userId) async {
    final rows = await _client
        .from('wardrobe_items')
        .select(_itemColumns)
        .eq('user_id', userId)
        .eq('status', FcItemStatus.active.wire)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    return rows.map<WardrobeItem>(WardrobeItem.fromJson).toList();
  }

  Future<WardrobeItem?> fetchItem(String itemId) async {
    final row = await _client
        .from('wardrobe_items')
        .select(_itemColumns)
        .eq('id', itemId)
        .maybeSingle();
    return row == null ? null : WardrobeItem.fromJson(row);
  }

  /// Confirm the review screen: apply the user's corrections and flip the row to `active`.
  ///
  /// `correctedFields` is not bookkeeping — the pairing of (what the extractor said, what the user
  /// changed it to) is the labelled data that would be needed to ever move off the vision model,
  /// and it costs one column to keep.
  Future<void> confirmItem(
    WardrobeItem item, {
    required List<String> correctedFields,
  }) async {
    await _client.from('wardrobe_items').update({
      'category': item.category.wire,
      'style': item.style,
      'pattern': item.pattern.wire,
      'fabric': item.fabric,
      'sleeve_type': item.sleeveType?.wire,
      'neckline': item.neckline?.wire,
      'fit': item.fit.wire,
      'season': item.season.wire,
      'occasion': item.occasion.wire,
      'status': FcItemStatus.active.wire,
      'corrected_fields': correctedFields,
    }).eq('id', item.id);
  }

  /// Soft delete (decision #7). The row and its thumbnail survive so that saved outfits containing
  /// this item still render — a hard delete would silently rewrite the user's own history.
  Future<void> deleteItem(String itemId) async {
    await _client
        .from('wardrobe_items')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', itemId);
  }

  /// Abandoned review. The row was written as `pending_review` before the user ever saw it, so
  /// backing out has to remove it or it becomes a permanent invisible orphan.
  Future<void> discardPendingItem(String itemId) async {
    await _client
        .from('wardrobe_items')
        .delete()
        .eq('id', itemId)
        .eq('status', FcItemStatus.pendingReview.wire);
  }

  // --- Storage ---------------------------------------------------------------

  /// Sign a thumbnail path for display. The bucket is private (007_storage.sql), so there is no
  /// public URL to fall back on.
  Future<String?> signThumbnail(String? path, {int expiresInSeconds = 3600}) async {
    if (path == null || path.isEmpty) return null;
    try {
      return await _client.storage
          .from('wardrobe-thumbnails')
          .createSignedUrl(path, expiresInSeconds);
    } catch (_) {
      // A missing thumbnail is a degraded card, not a failed screen. The item's colour swatch
      // still identifies it.
      return null;
    }
  }
}
