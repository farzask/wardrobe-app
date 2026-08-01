import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

/// Turns stored object paths into signed URLs, once.
///
/// The thumbnail bucket is private (007_storage.sql), so every image needs a signed URL. Signing is
/// a network round trip, and a grid of 150 items rebuilds constantly — signing inside the card's
/// build would fire hundreds of requests while the user scrolls.
///
/// So URLs are signed once per item and held until they near expiry. This is the reason
/// `wardrobe_items` stores a path rather than a URL: a URL persisted in the database would expire
/// and leave a permanently broken thumbnail, whereas a path can be re-signed forever.
class ThumbnailResolver extends ChangeNotifier {
  ThumbnailResolver(this._supabase);

  final SupabaseService _supabase;

  static const _ttl = Duration(hours: 1);
  // Re-sign a little before expiry so an image never fails mid-scroll.
  static const _refreshBefore = Duration(minutes: 5);

  final Map<String, _Signed> _cache = {};
  final Set<String> _inFlight = {};

  /// The signed URL if we have one, else null while it is being fetched.
  ///
  /// Returning null rather than a Future keeps the card synchronous: it renders its colour block
  /// immediately and the image fades in when ready, instead of every tile showing a spinner.
  String? urlFor(String? path) {
    if (path == null || path.isEmpty) return null;

    final cached = _cache[path];
    if (cached != null && !cached.isStale) return cached.url;

    _sign(path);
    return cached?.url;
  }

  Future<void> _sign(String path) async {
    if (_inFlight.contains(path)) return;
    _inFlight.add(path);
    try {
      final url = await _supabase.signThumbnail(path, expiresInSeconds: _ttl.inSeconds);
      if (url != null) {
        _cache[path] = _Signed(url, DateTime.now().add(_ttl));
        notifyListeners();
      }
    } finally {
      _inFlight.remove(path);
    }
  }

  void clear() {
    _cache.clear();
    _inFlight.clear();
  }
}

class _Signed {
  _Signed(this.url, this.expiresAt);

  final String url;
  final DateTime expiresAt;

  bool get isStale =>
      DateTime.now().isAfter(expiresAt.subtract(ThumbnailResolver._refreshBefore));
}
