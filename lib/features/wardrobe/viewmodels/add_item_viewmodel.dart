import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/services/backend_api_service.dart';
import '../../../core/services/image_capture_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/vocabulary/fc_vocabulary.dart';
import '../models/wardrobe_item.dart';

enum AddItemStage { idle, capturing, uploading, review, saving, failed, done }

/// Drives capture → extraction → review → save (PRD §4.2).
///
/// The review step is the one PRD §8 names as the abandonment risk, so this view model exists
/// mainly to make that step cheap: attributes arrive pre-filled, every correction is one tap, and
/// nothing blocks saving.
class AddItemViewModel extends ChangeNotifier {
  AddItemViewModel({
    required BackendApiService backend,
    required SupabaseService supabase,
    required ImageCaptureService capture,
  })  : _backend = backend,
        _supabase = supabase,
        _capture = capture;

  final BackendApiService _backend;
  final SupabaseService _supabase;
  final ImageCaptureService _capture;

  AddItemStage _stage = AddItemStage.idle;
  WardrobeItem? _draft;
  WardrobeItem? _asExtracted;
  String? _errorMessage;
  bool _errorRetryable = false;

  AddItemStage get stage => _stage;
  WardrobeItem? get draft => _draft;
  String? get errorMessage => _errorMessage;
  bool get errorRetryable => _errorRetryable;

  /// Which fields the user changed from what the extractor produced.
  ///
  /// Two jobs: the review screen marks them so the user can see their own edits, and they are
  /// persisted as the labelled data that would be needed to ever move off the vision model.
  final Set<String> _corrected = {};
  Set<String> get correctedFields => Set.unmodifiable(_corrected);

  /// Attribute keys ordered so the extractor's least-confident answers come first.
  ///
  /// Sorting alphabetically instead would put `category` — usually right — above `fabric`, usually
  /// a guess. The user should fix what is likely wrong, not what happens to sort early.
  List<String> get reviewOrder {
    final item = _draft;
    if (item == null) return const [];
    final keys = [
      'category', 'occasion', 'pattern', 'season', 'fit',
      'style', 'fabric', 'sleeve_type', 'neckline',
    ];
    keys.sort((a, b) {
      final ca = item.extractionConfidence[a] ?? 1.0;
      final cb = item.extractionConfidence[b] ?? 1.0;
      return ca.compareTo(cb);
    });
    return keys;
  }

  bool isLowConfidence(String field) =>
      (_draft?.extractionConfidence[field] ?? 1.0) < 0.7;

  Future<void> captureAndExtract({required bool fromCamera}) async {
    _stage = AddItemStage.capturing;
    _errorMessage = null;
    notifyListeners();

    File? file;
    try {
      file = await _capture.capture(fromCamera: fromCamera);
      if (file == null) {
        _stage = AddItemStage.idle;
        notifyListeners();
        return;
      }

      _stage = AddItemStage.uploading;
      notifyListeners();

      final result = await _backend.extractAttributes(file);
      _asExtracted = result.item;
      _draft = result.item;
      _corrected.clear();
      _stage = AddItemStage.review;
    } on BackendException catch (e) {
      _errorMessage = e.message;
      _errorRetryable = e.retryable;
      _stage = AddItemStage.failed;
    } catch (e) {
      _errorMessage = 'Could not read that photo. Try again with better light.';
      _errorRetryable = true;
      _stage = AddItemStage.failed;
    } finally {
      // PRD §4.2's promise has to hold on the device too — a temp copy left in the app's cache
      // directory is a photo FitCheck is keeping.
      if (file != null) await _capture.discard(file);
      notifyListeners();
    }
  }

  void edit(WardrobeItem Function(WardrobeItem) change, String field) {
    final current = _draft;
    if (current == null) return;
    _draft = change(current);
    _markCorrected(field);
    notifyListeners();
  }

  void _markCorrected(String field) {
    final original = _asExtracted;
    final now = _draft;
    if (original == null || now == null) return;
    // Compare against the extractor's answer, not against the previous value: a user who changes a
    // field and then changes it back has not corrected anything.
    if (_valueOf(original, field) == _valueOf(now, field)) {
      _corrected.remove(field);
    } else {
      _corrected.add(field);
    }
  }

  String? _valueOf(WardrobeItem item, String field) => switch (field) {
        'category' => item.category.wire,
        'occasion' => item.occasion.wire,
        'pattern' => item.pattern.wire,
        'season' => item.season.wire,
        'fit' => item.fit.wire,
        'style' => item.style,
        'fabric' => item.fabric,
        'sleeve_type' => item.sleeveType?.wire,
        'neckline' => item.neckline?.wire,
        _ => null,
      };

  /// Confirm the review. Flips the row from `pending_review` to `active`.
  Future<WardrobeItem?> save() async {
    final item = _draft;
    if (item == null) return null;

    _stage = AddItemStage.saving;
    notifyListeners();
    try {
      await _supabase.confirmItem(item, correctedFields: _corrected.toList());
      final saved = item.copyWith(status: FcItemStatus.active);
      _draft = saved;
      _stage = AddItemStage.done;
      notifyListeners();
      return saved;
    } catch (e) {
      _errorMessage = 'Could not save this item. Check your connection.';
      _errorRetryable = true;
      _stage = AddItemStage.review;
      notifyListeners();
      return null;
    }
  }

  /// Back out of the review. The row was written before the user saw it, so abandoning has to
  /// remove it — otherwise it becomes a permanent invisible orphan holding a thumbnail.
  Future<void> discard() async {
    final item = _draft;
    _draft = null;
    _asExtracted = null;
    _corrected.clear();
    _stage = AddItemStage.idle;
    notifyListeners();
    if (item != null) {
      try {
        await _supabase.discardPendingItem(item.id);
      } catch (_) {
        // The reaper query in 007_storage.sql is the backstop for this.
      }
    }
  }

  void reset() {
    _draft = null;
    _asExtracted = null;
    _corrected.clear();
    _errorMessage = null;
    _stage = AddItemStage.idle;
    notifyListeners();
  }
}
