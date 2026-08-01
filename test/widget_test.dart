import 'package:fitcheck/core/theme/app_colors.dart';
import 'package:fitcheck/core/theme/app_spacing.dart';
import 'package:fitcheck/core/vocabulary/fc_vocabulary.dart';
import 'package:fitcheck/core/widgets/fc_widgets.dart';
import 'package:fitcheck/core/widgets/item_card.dart';
import 'package:fitcheck/core/widgets/palette_stripe.dart';
import 'package:fitcheck/features/wardrobe/models/wardrobe_item.dart';
// Tristate is declared in dart:ui, not in package:flutter/semantics.dart.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  group('PaletteStripe', () {
    testWidgets('renders one band per palette colour', (tester) async {
      await tester.pumpWidget(harness(
        const PaletteStripe(
          palette: [
            PaletteColour(hex: '#c0392b', weight: 0.6),
            PaletteColour(hex: '#f2f2f0', weight: 0.4),
          ],
        ),
      ));

      final boxes = tester.widgetList<ColoredBox>(find.byType(ColoredBox));
      expect(boxes.map((b) => b.color), contains(const Color(0xFFC0392B)));
      expect(boxes.map((b) => b.color), contains(const Color(0xFFF2F2F0)));
    });

    testWidgets('sizes bands in proportion to weight', (tester) async {
      await tester.pumpWidget(harness(
        const SizedBox(
          height: 100,
          child: PaletteStripe(
            palette: [
              PaletteColour(hex: '#000000', weight: 0.75),
              PaletteColour(hex: '#ffffff', weight: 0.25),
            ],
          ),
        ),
      ));

      final flexes =
          tester.widgetList<Expanded>(find.byType(Expanded)).map((e) => e.flex).toList();
      expect(flexes.first, greaterThan(flexes.last));
    });

    testWidgets('never renders empty, even with no palette', (tester) async {
      // An item written before the palette column existed must still draw something.
      await tester.pumpWidget(harness(const PaletteStripe(palette: [])));
      expect(find.byType(ColoredBox), findsWidgets);
    });
  });

  group('OutfitPaletteBand', () {
    testWidgets('describes the outfit colours for screen readers', (tester) async {
      await tester.pumpWidget(harness(
        OutfitPaletteBand(items: [
          fakeItem(id: 'a', primaryColor: 'navy'),
          fakeItem(id: 'b', primaryColor: 'cream', colorHex: '#f0e6d2'),
        ]),
      ));

      expect(
        find.bySemanticsLabel(RegExp('navy, cream')),
        findsOneWidget,
      );
    });
  });

  group('ItemCard', () {
    testWidgets('shows the spec line, not just a photo', (tester) async {
      await tester.pumpWidget(harness(
        ItemCard(
          item: fakeItem(
            category: FcCategory.kurta,
            primaryColor: 'cream',
            occasion: FcOccasion.cultural,
          ),
          thumbnailUrl: null,
        ),
      ));

      expect(find.text('Kurta'), findsOneWidget);
      expect(find.text('CREAM · SOLID · CULTURAL'), findsOneWidget);
    });

    testWidgets('renders without a thumbnail rather than breaking', (tester) async {
      // The whole premise is attributes over photos — a missing thumbnail is a degraded card.
      await tester.pumpWidget(harness(
        ItemCard(item: fakeItem(), thumbnailUrl: null),
      ));
      expect(find.byIcon(Icons.checkroom_outlined), findsOneWidget);
    });

    testWidgets('marks the weak link with an icon and words, not colour alone',
        (tester) async {
      // The palette is achromatic precisely so meaning cannot leak into hue, and this app's users
      // are disproportionately likely to care about colour vision.
      await tester.pumpWidget(harness(
        ItemCard(
          item: fakeItem(),
          thumbnailUrl: null,
          flagged: true,
          flagLabel: 'Weak link',
        ),
      ));

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('WEAK LINK'), findsOneWidget);
    });

    testWidgets('announces selection to screen readers', (tester) async {
      await tester.pumpWidget(harness(
        ItemCard(item: fakeItem(), thumbnailUrl: null, selected: true, onTap: () {}),
      ));

      // `isSelected` is a tristate, not a bool: "not selected" and "selection is not a concept
      // here" are different things to a screen reader, and only the first should announce.
      final semantics = tester.getSemantics(find.byType(ItemCard));
      expect(semantics.flagsCollection.isSelected, Tristate.isTrue);
    });
  });

  group('FcChip', () {
    testWidgets('meets the minimum tap target', (tester) async {
      // Chips in a dense row are the classic 48px violation.
      await tester.pumpWidget(harness(FcChip(label: 'Formal', onTap: () {})));
      final size = tester.getSize(find.byType(FcChip));
      expect(size.height, greaterThanOrEqualTo(AppSpacing.minTapTarget));
    });

    testWidgets('marks an uncertain field without using colour', (tester) async {
      await tester.pumpWidget(harness(const FcChip(label: 'Cotton', marked: true)));
      expect(find.byType(Container), findsWidgets);
      expect(find.text('Cotton'), findsOneWidget);
    });
  });

  group('FcNotice', () {
    testWidgets('an empty state offers an action', (tester) async {
      var tapped = false;
      await tester.pumpWidget(harness(
        FcNotice(
          icon: Icons.filter_alt_off_outlined,
          title: 'Nothing matches those filters',
          body: 'You own 12 items, but none in this combination.',
          actionLabel: 'Clear filters',
          onAction: () => tapped = true,
        ),
      ));

      await tester.tap(find.text('Clear filters'));
      expect(tapped, isTrue);
    });
  });

  group('FcOfflineBanner', () {
    testWidgets('says when the data is from, not just that we are offline',
        (tester) async {
      await tester.pumpWidget(harness(
        FcOfflineBanner(
          cachedAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      ));
      expect(find.textContaining('2h ago'), findsOneWidget);
    });

    testWidgets('handles never having synced', (tester) async {
      await tester.pumpWidget(harness(const FcOfflineBanner(cachedAt: null)));
      expect(find.textContaining('saved wardrobe'), findsOneWidget);
    });
  });

  group('FcPrivacyNote', () {
    testWidgets('states the third-party retention plainly', (tester) async {
      // Required copy, not optional — decision #5 put extraction on Gemini's free tier, where
      // Google may retain submitted images. PRD §4.2 was corrected to say so.
      await tester.pumpWidget(harness(const FcPrivacyNote()));
      expect(find.textContaining('Gemini'), findsOneWidget);
      expect(find.textContaining('may keep it'), findsOneWidget);
    });
  });

  group('theme', () {
    for (final brightness in Brightness.values) {
      testWidgets('builds and renders in ${brightness.name}', (tester) async {
        await tester.pumpWidget(harness(
          Builder(
            builder: (context) {
              final palette = AppColors.of(context);
              // Every token must exist in both themes. Reading them all here means a token added
              // to one and not the other fails rather than silently falling back.
              return Column(
                children: [
                  ColoredBox(color: palette.surface, child: const SizedBox(width: 8, height: 8)),
                  ColoredBox(color: palette.surfaceRaised, child: const SizedBox(width: 8, height: 8)),
                  ColoredBox(color: palette.surfaceSunken, child: const SizedBox(width: 8, height: 8)),
                  ColoredBox(color: palette.onSurface, child: const SizedBox(width: 8, height: 8)),
                  ColoredBox(color: palette.onSurfaceMuted, child: const SizedBox(width: 8, height: 8)),
                  ColoredBox(color: palette.outline, child: const SizedBox(width: 8, height: 8)),
                  ColoredBox(color: palette.outlineStrong, child: const SizedBox(width: 8, height: 8)),
                  ColoredBox(color: palette.danger, child: const SizedBox(width: 8, height: 8)),
                ],
              );
            },
          ),
          brightness: brightness,
        ));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a pale garment swatch still gets a visible border', (tester) async {
      // Cream is one of the most common colours in the wardrobes this app targets, and without
      // this it is invisible on a light surface.
      await tester.pumpWidget(harness(
        Builder(
          builder: (context) {
            final palette = AppColors.of(context);
            final paleBorder = palette.swatchBorder(const Color(0xFFF8F8F6));
            final darkBorder = palette.swatchBorder(const Color(0xFF101010));
            expect(paleBorder, isNot(darkBorder));
            return const SizedBox();
          },
        ),
      ));
    });
  });

  group('text scaling', () {
    testWidgets('the item card survives 200% text scale without overflowing',
        (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: harness(
            SizedBox(
              width: 200,
              height: 280,
              child: ItemCard(item: fakeItem(), thumbnailUrl: null),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
