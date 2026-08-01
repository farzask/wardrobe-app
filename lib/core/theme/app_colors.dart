import 'package:flutter/material.dart';

/// FitCheck's palette.
///
/// THE RULE: **the chrome is achromatic. The only colour in this app comes from the user's
/// clothes.**
///
/// This is a functional constraint before it is an aesthetic one. Every screen puts UI surfaces
/// directly beside garment colour swatches, and simultaneous contrast is real — a warm cream
/// background makes a navy shirt read colder than it is, and a tinted card makes two greys look
/// like two different colours. An app whose entire compatibility engine runs on perceptual colour
/// distance cannot afford chrome that biases the user's perception of the very colours it is
/// scoring. So the greys below are true neutrals, not warm or cool ones.
///
/// The pleasant side effect: because no meaning can be carried by hue, meaning has to be carried by
/// icon, weight, and rule instead — which is exactly what
/// `skills/ui-ux-design/SKILL.md` §6 requires for colour-blind users anyway.
///
/// ONE EXCEPTION, stated rather than smuggled in: [danger] is a real red, reserved for destructive
/// confirmation and hard failure. It is never decorative and never rendered adjacent to a garment
/// swatch.
abstract final class AppColors {
  const AppColors._();

  // Light -------------------------------------------------------------------
  static const _lightSurface = Color(0xFFFCFCFC);
  static const _lightSurfaceRaised = Color(0xFFFFFFFF);
  static const _lightSurfaceSunken = Color(0xFFF2F2F2);
  static const _lightOnSurface = Color(0xFF141414);
  static const _lightOnSurfaceMuted = Color(0xFF6B6B6B);
  static const _lightOutline = Color(0xFFDCDCDC);
  static const _lightOutlineStrong = Color(0xFF141414);

  // Dark --------------------------------------------------------------------
  static const _darkSurface = Color(0xFF0E0E0E);
  static const _darkSurfaceRaised = Color(0xFF1A1A1A);
  static const _darkSurfaceSunken = Color(0xFF070707);
  static const _darkOnSurface = Color(0xFFF2F2F2);
  static const _darkOnSurfaceMuted = Color(0xFF919191);
  static const _darkOutline = Color(0xFF303030);
  static const _darkOutlineStrong = Color(0xFFF2F2F2);

  /// Reserved. Destructive confirmation and hard failure only.
  static const dangerLight = Color(0xFFD6002A);
  static const dangerDark = Color(0xFFFF4D6D);

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>()!;

  static const light = AppPalette(
    surface: _lightSurface,
    surfaceRaised: _lightSurfaceRaised,
    surfaceSunken: _lightSurfaceSunken,
    onSurface: _lightOnSurface,
    onSurfaceMuted: _lightOnSurfaceMuted,
    outline: _lightOutline,
    outlineStrong: _lightOutlineStrong,
    danger: dangerLight,
    onDanger: Color(0xFFFFFFFF),
  );

  static const dark = AppPalette(
    surface: _darkSurface,
    surfaceRaised: _darkSurfaceRaised,
    surfaceSunken: _darkSurfaceSunken,
    onSurface: _darkOnSurface,
    onSurfaceMuted: _darkOnSurfaceMuted,
    outline: _darkOutline,
    outlineStrong: _darkOutlineStrong,
    danger: dangerDark,
    onDanger: Color(0xFF141414),
  );
}

/// Semantic tokens. Named for role, never for appearance — `danger`, not `red` — so the whole
/// system can be retuned in one place.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.outline,
    required this.outlineStrong,
    required this.danger,
    required this.onDanger,
  });

  final Color surface;
  final Color surfaceRaised;
  final Color surfaceSunken;
  final Color onSurface;
  final Color onSurfaceMuted;

  /// Hairline separators.
  final Color outline;

  /// The heavy rule that marks the weak link and the current selection. Meaning is carried by
  /// weight here, not by hue.
  final Color outlineStrong;

  final Color danger;
  final Color onDanger;

  /// A border for a garment swatch.
  ///
  /// Without this, a white or cream garment is invisible against a light surface — and cream is
  /// one of the most common colours in the wardrobes this app targets.
  Color swatchBorder(Color swatch) {
    final isPale = swatch.computeLuminance() > 0.75;
    return isPale ? onSurfaceMuted : outline;
  }

  @override
  AppPalette copyWith({
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceSunken,
    Color? onSurface,
    Color? onSurfaceMuted,
    Color? outline,
    Color? outlineStrong,
    Color? danger,
    Color? onDanger,
  }) {
    return AppPalette(
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
      outline: outline ?? this.outline,
      outlineStrong: outlineStrong ?? this.outlineStrong,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceMuted: Color.lerp(onSurfaceMuted, other.onSurfaceMuted, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      outlineStrong: Color.lerp(outlineStrong, other.outlineStrong, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
    );
  }
}

/// Parse a `#rrggbb` from the database into a [Color].
///
/// Garment colour is data, not a token: it is rendered exactly as stored and never mapped onto the
/// palette. The user's navy shirt must look navy.
Color colorFromHex(String hex) {
  final cleaned = hex.replaceFirst('#', '').trim();
  if (cleaned.length != 6) return const Color(0xFF808080);
  final value = int.tryParse(cleaned, radix: 16);
  return value == null ? const Color(0xFF808080) : Color(0xFF000000 | value);
}
