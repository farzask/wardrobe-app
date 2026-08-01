import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Coarse colour groups for the wardrobe filter (PRD §4.3).
///
/// **Deliberately not a database enum**, and deliberately not the colour model the compatibility
/// engine uses. Two different jobs:
///
/// - *Scoring* asks "do these two colours work together", which needs perceptual distance
///   (CIEDE2000 over CIELAB) and is done on the server against the stored palette.
/// - *Filtering* asks "show me my green things", which is a human-language bucket. A person
///   looking for green does not want a perceptual neighbourhood, they want the drawer labelled
///   green.
///
/// So this is a plain hue classification computed on device from the stored hex. It is an
/// approximation and is allowed to be — nothing downstream depends on it, and it never touches a
/// score.
enum FcColourFamily {
  neutral('Black, white & grey'),
  brown('Brown & beige'),
  red('Red'),
  orange('Orange'),
  yellow('Yellow'),
  green('Green'),
  blue('Blue'),
  purple('Purple'),
  pink('Pink');

  const FcColourFamily(this.label);

  final String label;

  /// Classify a stored `#rrggbb`.
  static FcColourFamily fromHex(String hex) {
    final hsv = HSVColor.fromColor(colorFromHex(hex));

    // Order matters. Chroma is checked before hue because the hue angle of a near-grey is
    // essentially noise — classifying charcoal as "orange" because its hue rounds that way is the
    // most visible way this could be wrong.
    if (hsv.saturation < 0.15 || hsv.value < 0.12 || (hsv.value > 0.93 && hsv.saturation < 0.10)) {
      return FcColourFamily.neutral;
    }

    final hue = hsv.hue;

    // Brown is not a hue — it is a dark, desaturated orange. Without this case every beige kurta
    // and every tan shoe lands under "orange", which is not a drawer anyone looks in.
    if (hue >= 15 && hue < 50 && (hsv.value < 0.75 || hsv.saturation < 0.55)) {
      return FcColourFamily.brown;
    }

    // Pink is likewise a light red rather than its own hue band.
    if ((hue >= 330 || hue < 15) && hsv.value > 0.75 && hsv.saturation < 0.6) {
      return FcColourFamily.pink;
    }

    if (hue < 15 || hue >= 345) return FcColourFamily.red;
    if (hue < 45) return FcColourFamily.orange;
    if (hue < 70) return FcColourFamily.yellow;
    if (hue < 165) return FcColourFamily.green;
    if (hue < 260) return FcColourFamily.blue;
    if (hue < 290) return FcColourFamily.purple;
    if (hue < 345) return FcColourFamily.pink;
    return FcColourFamily.red;
  }

  /// A representative swatch for the filter chip, so the user picks a colour by seeing it rather
  /// than by reading a word.
  Color get swatch => switch (this) {
        FcColourFamily.neutral => const Color(0xFF9A9A9A),
        FcColourFamily.brown => const Color(0xFF8B6A44),
        FcColourFamily.red => const Color(0xFFC0392B),
        FcColourFamily.orange => const Color(0xFFE67E22),
        FcColourFamily.yellow => const Color(0xFFD9C216),
        FcColourFamily.green => const Color(0xFF2E8B57),
        FcColourFamily.blue => const Color(0xFF2E5F8A),
        FcColourFamily.purple => const Color(0xFF6C4A9E),
        FcColourFamily.pink => const Color(0xFFD98CA6),
      };
}
