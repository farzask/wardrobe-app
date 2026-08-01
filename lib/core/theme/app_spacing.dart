/// Spacing scale. If a value is not here, add it here rather than inlining it.
///
/// A 4pt base, geometric after 16. The jumps are deliberately large: with an achromatic palette
/// there is no colour to separate regions, so whitespace is doing the structural work and small
/// inconsistencies read as mistakes.
abstract final class AppSpacing {
  const AppSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Horizontal page gutter. One value everywhere, so every screen's content starts on the same
  /// vertical line — the cheapest way to make a set of screens feel like one product.
  static const double gutter = md;

  /// Minimum tap target. Chips and icon buttons violate this by default.
  static const double minTapTarget = 48;
}
