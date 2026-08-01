import 'package:flutter/material.dart';

import '../../features/wardrobe/models/wardrobe_item.dart';
import '../theme/app_colors.dart';

/// FitCheck's signature element: an item's measured colour palette, rendered as a stripe with each
/// band sized by that colour's share of the garment.
///
/// This exists because of decision #4 — storing a weighted palette instead of one averaged hex. A
/// red-and-white striped shirt shows two bands, red and white, in proportion. A plain navy trouser
/// shows one solid band. The schema decision becomes something the user can see, and two garments
/// that "are both blue" become visibly different at a glance.
///
/// It is also the only colour in the app that is not chrome — see the rule at the top of
/// `app_colors.dart`.
class PaletteStripe extends StatelessWidget {
  const PaletteStripe({
    super.key,
    required this.palette,
    this.axis = Axis.vertical,
    this.thickness = 6,
    this.borderRadius,
  });

  final List<PaletteColour> palette;
  final Axis axis;
  final double thickness;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final entries = palette.isEmpty
        ? const [PaletteColour(hex: '#808080', weight: 1.0)]
        : palette;

    // Flex needs integers, and a band under ~4% of the stripe is invisible anyway — floor it so a
    // minor colour still reads as present rather than vanishing.
    final flexes = entries
        .map((e) => (e.weight * 1000).round().clamp(40, 1000))
        .toList();

    final bands = <Widget>[
      for (var i = 0; i < entries.length; i++)
        Expanded(
          flex: flexes[i],
          child: ColoredBox(color: colorFromHex(entries[i].hex)),
        ),
    ];

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: DecoratedBox(
        // Without an outline a white or cream garment is invisible against a light surface, and
        // cream is one of the most common colours in the wardrobes this app targets.
        decoration: BoxDecoration(
          border: Border.all(color: colors.outline, width: 0.5),
        ),
        child: SizedBox(
          width: axis == Axis.vertical ? thickness : null,
          height: axis == Axis.horizontal ? thickness : null,
          child: axis == Axis.vertical
              ? Column(children: bands)
              : Row(children: bands),
        ),
      ),
    );
  }
}

/// The whole outfit's colour, read as one continuous band.
///
/// This is what the compatibility engine is actually scoring, made visible: the user can see the
/// clash before reading a word of the verdict.
class OutfitPaletteBand extends StatelessWidget {
  const OutfitPaletteBand({
    super.key,
    required this.items,
    this.height = 10,
  });

  final List<WardrobeItem> items;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (items.isEmpty) {
      return SizedBox(
        height: height,
        child: ColoredBox(color: colors.surfaceSunken),
      );
    }

    return Semantics(
      label: 'Colours in this outfit: '
          '${items.map((i) => i.primaryColor).join(', ')}',
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (final item in items)
              Expanded(
                child: PaletteStripe(
                  palette: item.effectivePalette,
                  axis: Axis.horizontal,
                  thickness: height,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
