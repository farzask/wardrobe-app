import 'package:flutter/widgets.dart';

/// Corner radii.
///
/// Kept tight. The item card is a specimen swatch, and a specimen swatch with soft corners reads
/// as a toy rather than as a measurement.
abstract final class AppRadius {
  const AppRadius._();

  static const double none = 0;
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 14;
  static const double pill = 999;

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(md));
  static const BorderRadius sheetRadius =
      BorderRadius.vertical(top: Radius.circular(lg));
  static const BorderRadius chipRadius = BorderRadius.all(Radius.circular(pill));
}
