import 'package:fitcheck/core/theme/app_colors.dart';
import 'package:fitcheck/core/vocabulary/colour_family.dart';
import 'package:fitcheck/core/vocabulary/fc_vocabulary.dart';
import 'package:fitcheck/features/auth/models/profile.dart';
import 'package:fitcheck/features/wardrobe/models/wardrobe_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  group('WardrobeItem', () {
    test('round-trips through JSON', () {
      final original = fakeItem(id: 'a', category: FcCategory.kurta);
      final restored = WardrobeItem.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.category, FcCategory.kurta);
      expect(restored.occasion, original.occasion);
      expect(restored.palette.length, original.palette.length);
      expect(restored.palette.first.hex, original.palette.first.hex);
    });

    test('decodes a palette stored as a JSON string', () {
      // Postgres returns jsonb as a List; the SQLite cache stores it as text. Both must parse, or
      // the offline path renders every item grey.
      final item = WardrobeItem.fromJson({
        ...fakeItem().toJson(),
        'color_palette': '[{"hex":"#112233","weight":1.0}]',
      });
      expect(item.palette.single.hex, '#112233');
    });

    test('falls back to the dominant colour when no palette is stored', () {
      final item = WardrobeItem.fromJson({
        ...fakeItem().toJson(),
        'color_palette': null,
      });
      expect(item.palette, isEmpty);
      expect(item.effectivePalette.single.hex, item.colorHex);
      expect(item.effectivePalette.single.weight, 1.0);
    });

    test('maps category to the slot the outfit builder groups by', () {
      expect(fakeItem(category: FcCategory.kurta).slot, FcSlot.top);
      expect(fakeItem(category: FcCategory.shalwar).slot, FcSlot.bottom);
      expect(fakeItem(category: FcCategory.frock).slot, FcSlot.fullBody);
      expect(fakeItem(category: FcCategory.dupatta).slot, FcSlot.drape);
    });

    test('copyWith can clear a nullable attribute', () {
      // `?? this.x` cannot express "set this to null", so without the explicit clear flags the user
      // could never remove a wrongly-detected neckline on the review screen.
      final item = fakeItem().copyWith(neckline: FcNeckline.collar);
      expect(item.neckline, FcNeckline.collar);
      expect(item.copyWith(clearNeckline: true).neckline, isNull);
    });
  });

  group('Profile', () {
    test('a new account with no gender needs onboarding', () {
      const profile = Profile(id: 'u1');
      expect(profile.needsOnboarding, isTrue);
      expect(profile.isOnboardingComplete, isFalse);
    });

    test('a female profile is complete once gender is set', () {
      const profile = Profile(id: 'u1', gender: FcGender.female);
      expect(profile.isOnboardingComplete, isTrue);
    });

    test('a male profile is incomplete until the accessory question is answered', () {
      const unanswered = Profile(id: 'u1', gender: FcGender.male);
      expect(unanswered.isOnboardingComplete, isFalse);

      const answeredNo =
          Profile(id: 'u1', gender: FcGender.male, wearsAccessories: false);
      expect(answeredNo.isOnboardingComplete, isTrue);
    });
  });

  group('vocabulary', () {
    test('every category has a slot', () {
      // A category with no slot is invisible to the outfit builder and unreachable by the swap
      // engine. The same assertion runs in SQL and in Python.
      for (final category in FcCategory.values) {
        expect(kCategorySlot[category], isNotNull, reason: category.wire);
      }
    });

    test('wire values round-trip', () {
      for (final occasion in FcOccasion.values) {
        expect(FcOccasion.fromWire(occasion.wire), occasion);
      }
      for (final category in FcCategory.values) {
        expect(FcCategory.fromWire(category.wire), category);
      }
    });

    test('nullable enums accept null without throwing', () {
      expect(FcSleeveType.fromWire(null), isNull);
      expect(FcNeckline.fromWire(null), isNull);
      expect(FcGender.fromWire(null), isNull);
    });
  });

  group('FcColourFamily', () {
    test('classifies plain hues', () {
      expect(FcColourFamily.fromHex('#c0392b'), FcColourFamily.red);
      expect(FcColourFamily.fromHex('#2e8b57'), FcColourFamily.green);
      expect(FcColourFamily.fromHex('#1b2a4a'), FcColourFamily.blue);
      expect(FcColourFamily.fromHex('#6c4a9e'), FcColourFamily.purple);
    });

    test('treats greys, black and white as neutral', () {
      // A near-grey has an essentially random hue angle. Filing charcoal under "orange" because
      // its hue rounds that way is the most visible way this could be wrong.
      expect(FcColourFamily.fromHex('#8a8a8a'), FcColourFamily.neutral);
      expect(FcColourFamily.fromHex('#000000'), FcColourFamily.neutral);
      expect(FcColourFamily.fromHex('#ffffff'), FcColourFamily.neutral);
      expect(FcColourFamily.fromHex('#1a1a1a'), FcColourFamily.neutral);
    });

    test('brown and beige are not filed under orange', () {
      // Brown is a dark, desaturated orange rather than its own hue band. Without the special
      // case, every beige kurta and tan shoe lands in a drawer nobody looks in.
      expect(FcColourFamily.fromHex('#8b6a44'), FcColourFamily.brown);
      expect(FcColourFamily.fromHex('#d9c9a3'), FcColourFamily.brown);
      expect(FcColourFamily.fromHex('#e67e22'), FcColourFamily.orange);
    });

    test('pink is separated from red', () {
      expect(FcColourFamily.fromHex('#d98ca6'), FcColourFamily.pink);
      expect(FcColourFamily.fromHex('#8b0000'), FcColourFamily.red);
    });

    test('an item is filed under every substantial colour it contains', () {
      // A navy shirt with a broad cream stripe belongs in both drawers, because the user thinks of
      // it as both.
      final striped = fakeItem(
        colorHex: '#1b2a4a',
        palette: const [
          PaletteColour(hex: '#1b2a4a', weight: 0.6),
          PaletteColour(hex: '#f2f0ea', weight: 0.4),
        ],
      );
      expect(striped.colourFamilies,
          containsAll([FcColourFamily.blue, FcColourFamily.neutral]));
    });

    test('a sliver of colour does not define the garment', () {
      final mostlyNavy = fakeItem(
        colorHex: '#1b2a4a',
        palette: const [
          PaletteColour(hex: '#1b2a4a', weight: 0.95),
          PaletteColour(hex: '#c0392b', weight: 0.05),
        ],
      );
      expect(mostlyNavy.colourFamilies, isNot(contains(FcColourFamily.red)));
    });
  });

  group('colorFromHex', () {
    test('parses a garment colour exactly', () {
      // Garment colour is data, never mapped onto the palette. The user's navy shirt must be navy.
      expect(colorFromHex('#1b2a4a'), const Color(0xFF1B2A4A));
      expect(colorFromHex('1b2a4a'), const Color(0xFF1B2A4A));
    });

    test('degrades to grey rather than throwing on bad input', () {
      // A malformed hex must not take down the whole wardrobe grid.
      expect(colorFromHex('nope'), const Color(0xFF808080));
      expect(colorFromHex(''), const Color(0xFF808080));
    });
  });
}
