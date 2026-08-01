import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Camera and gallery capture, with a client-side downscale before upload.
///
/// The downscale is the single largest win available to perceived speed. A phone camera produces a
/// 3–6 MB image; the vision model reads attributes perfectly well from ~1024px. Upload time
/// dominates the "few seconds" PRD §6 asks for, so shrinking before sending cuts the wait by close
/// to an order of magnitude and costs nothing in accuracy.
///
/// The *crop* still happens server-side, because it needs the model's bounding box.
class ImageCaptureService {
  ImageCaptureService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  static const int _maxEdge = 1024;
  static const int _jpegQuality = 88;

  Future<File?> capture({required bool fromCamera}) async {
    final picked = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      // image_picker resizes natively where the platform supports it, which is much faster than
      // decoding in Dart. `_downscale` below is the fallback for when it does not.
      maxWidth: _maxEdge.toDouble(),
      maxHeight: _maxEdge.toDouble(),
      imageQuality: _jpegQuality,
    );
    if (picked == null) return null;
    return _downscale(File(picked.path));
  }

  /// Re-encode to a bounded size. Runs after `pickImage` because the platform's own resize is
  /// advisory — on some Android devices it returns the original when the plugin cannot decode it.
  Future<File> _downscale(File source) async {
    final bytes = await source.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return source;

    if (decoded.width <= _maxEdge && decoded.height <= _maxEdge) return source;

    final resized = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: _maxEdge)
        : img.copyResize(decoded, height: _maxEdge);

    final dir = await getTemporaryDirectory();
    final target = File(p.join(
      dir.path,
      'fitcheck_upload_${DateTime.now().microsecondsSinceEpoch}.jpg',
    ));
    await target.writeAsBytes(img.encodeJpg(resized, quality: _jpegQuality));
    return target;
  }

  /// Delete the local copy once it has been uploaded.
  ///
  /// PRD §4.2 promises FitCheck does not keep the original photo. That promise has to hold on the
  /// device too, not only on the server — a temp file left in the app's cache directory is a copy
  /// FitCheck is keeping.
  Future<void> discard(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort. A file the OS will clear from the temp directory anyway is not worth
      // failing the user's save over.
    }
  }
}
