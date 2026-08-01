import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../features/outfit/models/outfit_result.dart';
import '../../features/wardrobe/models/wardrobe_item.dart';
import '../config/app_config.dart';

/// Distinguishes a failure the user can retry from one they cannot.
///
/// The UI has separate `failed-retryable` and `failed-fatal` states, and an HTTP status alone
/// cannot tell them apart — a 400 for "that photo has no garment in it" and a 400 for "the request
/// was malformed" want completely different screens. The backend returns the flag explicitly.
class BackendException implements Exception {
  BackendException(this.message, {required this.retryable, this.code});

  final String message;
  final bool retryable;
  final String? code;

  @override
  String toString() => message;
}

class ExtractionResult {
  const ExtractionResult({required this.item, required this.confidence});

  final WardrobeItem item;
  final Map<String, double> confidence;
}

/// The only two calls that leave the app for anything other than Supabase, per TRD §1.
class BackendApiService {
  BackendApiService({http.Client? client, required this.tokenProvider})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// Read at call time, not construction time: access tokens are refreshed by the Supabase SDK, and
  /// a token captured once would start failing silently an hour into a session.
  final String? Function() tokenProvider;

  Uri _url(String path) => Uri.parse('${AppConfig.backendUrl}$path');

  Map<String, String> _headers() {
    final token = tokenProvider();
    if (token == null) {
      throw BackendException('You are signed out. Sign in and try again.',
          retryable: false, code: 'unauthenticated');
    }
    return {'Authorization': 'Bearer $token'};
  }

  Never _throwFrom(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final error = body['error'] as Map<String, dynamic>;
      throw BackendException(
        error['message'] as String,
        retryable: error['retryable'] as bool? ?? false,
        code: error['code'] as String?,
      );
    } on BackendException {
      rethrow;
    } catch (_) {
      // The envelope was missing or malformed — a gateway error page, usually. 5xx is worth
      // retrying; anything else is not.
      throw BackendException(
        'The server returned an unexpected response (${response.statusCode}).',
        retryable: response.statusCode >= 500,
      );
    }
  }

  /// PRD §4.2 — photograph an item, get its attributes back.
  ///
  /// The backend writes the row as `pending_review` and returns its id; the review screen confirms
  /// it. That inverts TRD §4.7 in favour of TRD §1's own recommendation, so the client never
  /// handles raw model output and an abandoned review leaves a findable row rather than an orphaned
  /// storage object.
  Future<ExtractionResult> extractAttributes(File image) async {
    final request = http.MultipartRequest('POST', _url('/v1/extract-attributes'))
      ..headers.addAll(_headers())
      ..files.add(await http.MultipartFile.fromPath('image', image.path));

    final response = await _send(request);
    if (response.statusCode != 200) _throwFrom(response);

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final attributes = body['attributes'] as Map<String, dynamic>;
    final confidence = (body['confidence'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, (v as num).toDouble()));

    return ExtractionResult(
      item: WardrobeItem.fromJson({
        ...attributes,
        'id': body['item_id'],
        'thumbnail_path': body['thumbnail_path'],
        'status': 'pending_review',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'extraction_confidence': confidence,
      }),
      confidence: confidence,
    );
  }

  /// PRD §4.4(a) — the primary path. Pure arithmetic over attributes already stored.
  Future<OutfitResult> evaluateOutfit({
    required List<String> itemIds,
    String? name,
    bool persist = true,
  }) async {
    final response = await _client.post(
      _url('/v1/evaluate-outfit'),
      headers: {..._headers(), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'wardrobe_item_ids': itemIds,
        'name': name,
        'persist': persist,
      }),
    );
    if (response.statusCode != 200) _throwFrom(response);
    return OutfitResult.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<http.Response> _send(http.MultipartRequest request) async {
    final streamed = await _client.send(request);
    return http.Response.fromStream(streamed);
  }

  void dispose() => _client.close();
}
