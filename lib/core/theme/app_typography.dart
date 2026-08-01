import 'package:flutter/material.dart';

/// Type system.
///
/// Three roles, and the third is the one that gives FitCheck its character:
///
/// - **display** — verdicts and screen titles. Heavy, tightly tracked, set large.
/// - **body** — prose the user reads.
/// - **mono** — every measurement. Hex codes, LAB values, scores, attribute keys, item counts.
///
/// The monospace role is not decoration. This app's content genuinely *is* measurement — a
/// wardrobe item is a colour plus a spec sheet — and setting those values in tracked, uppercase
/// mono is what makes a card read as a tailor's specimen label rather than a generic list row.
/// It is also the only way to make hex codes scannable when they sit in a column.
///
/// FONTS: these use the platform's default families rather than bundled files. The personality
/// here comes from scale, weight, and tracking, which is where most of it lives anyway. Bundling a
/// display face would sharpen it further and is a change to this one file plus `pubspec.yaml` —
/// deliberately not done here, because it means committing binary font assets and their licences,
/// which is the user's call to make and not something to slip into a build.
abstract final class AppTypography {
  const AppTypography._();

  /// Platform monospace. Flutter resolves these per-platform; the fallback chain matters because
  /// naming only one gets silently substituted on the platform that lacks it.
  static const List<String> monoFallback = <String>[
    'SF Mono',
    'Menlo',
    'Roboto Mono',
    'DroidSansMono',
    'Consolas',
    'monospace',
  ];

  static TextTheme textTheme(Color onSurface, Color onSurfaceMuted) {
    return TextTheme(
      // Display — verdicts. Negative tracking at this size stops it reading as a system alert.
      displayLarge: TextStyle(
        fontSize: 40,
        height: 1.05,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
        color: onSurface,
      ),
      displayMedium: TextStyle(
        fontSize: 30,
        height: 1.12,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        color: onSurface,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        color: onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: onSurface,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: onSurface,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: onSurfaceMuted,
      ),
      labelLarge: TextStyle(
        fontSize: 15,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: onSurface,
      ),
    );
  }

  /// The utility role. Small, uppercase, widely tracked — an instrument label.
  static TextStyle mono(Color color, {double size = 11, FontWeight? weight}) {
    return TextStyle(
      fontFamily: monoFallback.first,
      fontFamilyFallback: monoFallback.sublist(1),
      fontSize: size,
      height: 1.3,
      fontWeight: weight ?? FontWeight.w500,
      letterSpacing: 0.8,
      color: color,
    );
  }

  /// A score, a count, a hex value — mono at reading size, not tracked as hard as a label.
  static TextStyle monoValue(Color color, {double size = 15}) {
    return TextStyle(
      fontFamily: monoFallback.first,
      fontFamilyFallback: monoFallback.sublist(1),
      fontSize: size,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      color: color,
    );
  }
}
