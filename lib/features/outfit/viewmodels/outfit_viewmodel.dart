import 'package:flutter/foundation.dart';

import '../../../core/services/backend_api_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/vocabulary/fc_vocabulary.dart';
import '../../wardrobe/models/wardrobe_item.dart';
import '../models/outfit_result.dart';

enum OutfitStage { building, evaluating, result, offlineBlocked, failed }

/// Outfit builder and result (PRD §4.4a).
class OutfitViewModel extends ChangeNotifier {
  OutfitViewModel({
    required BackendApiService backend,
    required ConnectivityService connectivity,
  })  : _backend = backend,
        _connectivity = connectivity;

  final BackendApiService _backend;
  final ConnectivityService _connectivity;

  final List<WardrobeItem> _selected = [];
  OutfitStage _stage = OutfitStage.building;
  OutfitResult? _result;
  String? _errorMessage;
  bool _errorRetryable = false;

  List<WardrobeItem> get selected => List.unmodifiable(_selected);
  OutfitStage get stage => _stage;
  OutfitResult? get result => _result;
  String? get errorMessage => _errorMessage;
  bool get errorRetryable => _errorRetryable;

  /// An outfit needs at least two garments — with one there is no pairing to score.
  bool get canEvaluate => _selected.length >= 2;

  bool isSelected(String itemId) => _selected.any((i) => i.id == itemId);

  /// Which slots are filled, so the builder can show the outfit as positions rather than as an
  /// undifferentiated list. This is what makes "swap this for that" legible.
  Map<FcSlot, List<WardrobeItem>> get bySlot {
    final map = <FcSlot, List<WardrobeItem>>{};
    for (final item in _selected) {
      map.putIfAbsent(item.slot, () => []).add(item);
    }
    return map;
  }

  void toggle(WardrobeItem item) {
    final index = _selected.indexWhere((i) => i.id == item.id);
    if (index >= 0) {
      _selected.removeAt(index);
    } else {
      _selected.add(item);
    }
    // Selecting a different item invalidates the previous verdict. Leaving it on screen would show
    // a score for an outfit the user is no longer looking at.
    _result = null;
    _stage = OutfitStage.building;
    notifyListeners();
  }

  void clear() {
    _selected.clear();
    _result = null;
    _stage = OutfitStage.building;
    notifyListeners();
  }

  Future<void> evaluate({String? name}) async {
    if (!canEvaluate) return;

    if (!await _connectivity.isOnline) {
      // PRD §6: browsing works offline, evaluating does not. Said plainly rather than as a failed
      // request, because the user can act on "you're offline" and cannot act on "request failed".
      _stage = OutfitStage.offlineBlocked;
      notifyListeners();
      return;
    }

    _stage = OutfitStage.evaluating;
    _errorMessage = null;
    notifyListeners();

    try {
      _result = await _backend.evaluateOutfit(
        itemIds: _selected.map((i) => i.id).toList(),
        name: name,
      );
      _stage = OutfitStage.result;
    } on BackendException catch (e) {
      _errorMessage = e.message;
      _errorRetryable = e.retryable;
      _stage = OutfitStage.failed;
    } catch (e) {
      _errorMessage = 'Could not check this outfit. Try again.';
      _errorRetryable = true;
      _stage = OutfitStage.failed;
    }
    notifyListeners();
  }

  /// Apply a suggested swap and re-check, closing the loop the result screen opens:
  /// select → evaluate → weak link → swap → evaluate again.
  Future<void> applySwap(SwapSuggestion suggestion, WardrobeItem replacement) async {
    final index = _selected.indexWhere((i) => i.id == suggestion.replacesItemId);
    if (index < 0) return;
    _selected[index] = replacement;
    notifyListeners();
    await evaluate();
  }

  WardrobeItem? get weakItem {
    final id = _result?.weakItemId;
    if (id == null) return null;
    for (final item in _selected) {
      if (item.id == id) return item;
    }
    return null;
  }

  void backToBuilding() {
    _stage = OutfitStage.building;
    notifyListeners();
  }
}
