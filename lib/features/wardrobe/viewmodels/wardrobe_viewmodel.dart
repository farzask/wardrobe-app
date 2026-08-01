import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/services/connectivity_service.dart';
import '../../../core/services/local_cache.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/vocabulary/colour_family.dart';
import '../../../core/vocabulary/fc_vocabulary.dart';
import '../models/wardrobe_item.dart';

/// The wardrobe grid's states. `empty` and `emptyAfterFilter` are separate on purpose: the first
/// means "you own nothing yet" and offers to add an item, the second means "you own nothing green
/// and formal" and offers to clear filters. Collapsing them produces a first-run screen that tells
/// a brand-new user to adjust filters they have never set.
enum WardrobeStatus { loading, loaded, empty, emptyAfterFilter, offlineCache, error }

/// PRD §4.3 names four filter dimensions: category, colour, season and occasion. All four are here.
class WardrobeFilters {
  const WardrobeFilters({this.category, this.occasion, this.season, this.colour});

  final FcCategory? category;
  final FcOccasion? occasion;
  final FcSeason? season;
  final FcColourFamily? colour;

  bool get isActive =>
      category != null || occasion != null || season != null || colour != null;

  int get count =>
      [category, occasion, season, colour].where((f) => f != null).length;

  WardrobeFilters copyWith({
    FcCategory? category,
    FcOccasion? occasion,
    FcSeason? season,
    FcColourFamily? colour,
    bool clearCategory = false,
    bool clearOccasion = false,
    bool clearSeason = false,
    bool clearColour = false,
  }) =>
      WardrobeFilters(
        category: clearCategory ? null : (category ?? this.category),
        occasion: clearOccasion ? null : (occasion ?? this.occasion),
        season: clearSeason ? null : (season ?? this.season),
        colour: clearColour ? null : (colour ?? this.colour),
      );

  static const none = WardrobeFilters();
}

class WardrobeViewModel extends ChangeNotifier {
  WardrobeViewModel({
    required SupabaseService supabase,
    required LocalCache cache,
    required ConnectivityService connectivity,
    required this.userId,
  })  : _supabase = supabase,
        _cache = cache,
        _connectivity = connectivity;

  final SupabaseService _supabase;
  final LocalCache _cache;
  final ConnectivityService _connectivity;
  final String userId;

  List<WardrobeItem> _all = const [];
  WardrobeFilters _filters = WardrobeFilters.none;
  WardrobeStatus _status = WardrobeStatus.loading;
  DateTime? _cachedAt;
  String? _errorMessage;

  WardrobeStatus get status => _status;
  WardrobeFilters get filters => _filters;
  DateTime? get cachedAt => _cachedAt;
  String? get errorMessage => _errorMessage;
  int get totalCount => _all.length;

  List<WardrobeItem> get items {
    if (!_filters.isActive) return _all;
    return _all.where((item) {
      if (_filters.category != null && item.category != _filters.category) return false;
      if (_filters.occasion != null && item.occasion != _filters.occasion) return false;
      if (_filters.season != null && item.season != _filters.season) return false;
      if (_filters.colour != null &&
          !item.colourFamilies.contains(_filters.colour)) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Only the colour families the user actually owns, ordered by how many items are in each.
  ///
  /// Same reasoning as [ownedCategories]: offering all nine when they own navy, white and cream
  /// makes them hunt through six options that return nothing.
  List<FcColourFamily> get ownedColours {
    final counts = <FcColourFamily, int>{};
    for (final item in _all) {
      for (final family in item.colourFamilies) {
        counts[family] = (counts[family] ?? 0) + 1;
      }
    }
    final owned = counts.keys.toList();
    owned.sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return owned;
  }

  /// Only the categories the user actually owns. Offering all 23 in the filter sheet when they own
  /// shirts and jeans makes the user hunt through mostly-empty options.
  List<FcCategory> get ownedCategories {
    final owned = _all.map((i) => i.category).toSet().toList();
    owned.sort((a, b) => a.label.compareTo(b.label));
    return owned;
  }

  Future<void> load() async {
    _status = WardrobeStatus.loading;
    notifyListeners();

    // Read the cache first, always. It makes a warm start instant, and it means a slow network
    // shows the user their wardrobe rather than a spinner.
    final cached = await _cache.readItems(userId);
    if (cached.isNotEmpty) {
      _all = cached;
      _cachedAt = await _cache.lastSyncedAt(userId);
      _settle(fromCache: true);
    }

    if (!await _connectivity.isOnline) {
      _cachedAt = await _cache.lastSyncedAt(userId);
      _settle(fromCache: true);
      return;
    }

    try {
      final fresh = await _supabase.fetchWardrobe(userId);
      _all = fresh;
      await _cache.replaceItems(userId, fresh);
      _cachedAt = DateTime.now();
      _settle(fromCache: false);
    } catch (e) {
      // A fetch failure with usable cached data is not an error the user needs to see — they get
      // their wardrobe and an "offline" banner. It is only an error when there is nothing to show.
      if (_all.isEmpty) {
        _errorMessage = 'Could not load your wardrobe.';
        _status = WardrobeStatus.error;
        notifyListeners();
      } else {
        _settle(fromCache: true);
      }
    }
  }

  void _settle({required bool fromCache}) {
    if (_all.isEmpty) {
      _status = WardrobeStatus.empty;
    } else if (items.isEmpty) {
      _status = WardrobeStatus.emptyAfterFilter;
    } else {
      _status = fromCache ? WardrobeStatus.offlineCache : WardrobeStatus.loaded;
    }
    notifyListeners();
  }

  void applyFilters(WardrobeFilters filters) {
    _filters = filters;
    _settle(fromCache: _status == WardrobeStatus.offlineCache);
  }

  void clearFilters() => applyFilters(WardrobeFilters.none);

  Future<void> deleteItem(String itemId) async {
    await _supabase.deleteItem(itemId);
    _all = _all.where((i) => i.id != itemId).toList();
    await _cache.replaceItems(userId, _all);
    _settle(fromCache: false);
  }

  /// Called after a successful add so the new item appears without a full refetch.
  void insert(WardrobeItem item) {
    _all = [item, ..._all];
    unawaited(_cache.replaceItems(userId, _all));
    _settle(fromCache: false);
  }

  WardrobeItem? byId(String id) {
    for (final item in _all) {
      if (item.id == id) return item;
    }
    return null;
  }
}
