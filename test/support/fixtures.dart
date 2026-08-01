import 'package:fitcheck/core/theme/app_theme.dart';
import 'package:fitcheck/core/vocabulary/fc_vocabulary.dart';
import 'package:fitcheck/features/wardrobe/models/wardrobe_item.dart';
import 'package:flutter/material.dart';

WardrobeItem fakeItem({
  String id = 'item-1',
  FcCategory category = FcCategory.shirt,
  FcOccasion occasion = FcOccasion.casual,
  FcSeason season = FcSeason.allSeason,
  FcPattern pattern = FcPattern.solid,
  String colorHex = '#1b2a4a',
  String primaryColor = 'navy',
  List<PaletteColour>? palette,
  Map<String, double> confidence = const {},
  String? thumbnailPath,
}) {
  return WardrobeItem(
    id: id,
    category: category,
    pattern: pattern,
    fit: FcFit.regular,
    season: season,
    occasion: occasion,
    colorHex: colorHex,
    palette: palette ?? [PaletteColour(hex: colorHex, weight: 1.0)],
    primaryColor: primaryColor,
    status: FcItemStatus.active,
    createdAt: DateTime(2026, 8, 1),
    thumbnailPath: thumbnailPath,
    extractionConfidence: confidence,
  );
}

/// Wraps a widget in enough app scaffolding to render, in whichever brightness is under test.
///
/// Both themes are exercised because the palette is built for both at once, and a token added to
/// one but not the other is a defect that only shows up when something is actually rendered in the
/// other.
Widget harness(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
    home: Scaffold(body: child),
  );
}
