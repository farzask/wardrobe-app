import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/thumbnail_resolver.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/fc_widgets.dart';
import '../../../core/widgets/palette_stripe.dart';
import '../models/wardrobe_item.dart';
import '../viewmodels/wardrobe_viewmodel.dart';

/// One item's full spec (PRD §4.3).
class ItemDetailView extends StatelessWidget {
  const ItemDetailView({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context) {
    final wardrobe = context.watch<WardrobeViewModel>();
    final item = wardrobe.byId(itemId);

    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const FcNotice(
          icon: Icons.search_off,
          title: 'Item not found',
          body: 'It may have been removed from another device.',
        ),
      );
    }

    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final thumbnailUrl = context.watch<ThumbnailResolver>().urlFor(item.thumbnailPath);

    return Scaffold(
      appBar: AppBar(
        title: Text(item.category.label),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove from wardrobe',
            onPressed: () => _confirmDelete(context, wardrobe, item),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.md,
          AppSpacing.gutter,
          AppSpacing.xxl,
        ),
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ClipRRect(
              borderRadius: AppRadius.cardRadius,
              child: Row(
                children: [
                  PaletteStripe(palette: item.effectivePalette, thickness: 14),
                  Expanded(
                    child: thumbnailUrl == null
                        ? ColoredBox(
                            color: colors.surfaceSunken,
                            child: Icon(Icons.checkroom_outlined,
                                size: 48, color: colors.onSurfaceMuted),
                          )
                        : Image.network(thumbnailUrl, fit: BoxFit.cover),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          Text('${item.primaryColor} ${item.category.label}'.trim(),
              style: text.displayMedium),
          if (item.style?.isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(item.style!, style: text.bodyLarge),
          ],
          const SizedBox(height: AppSpacing.lg),

          const FcLabel('Attributes'),
          const SizedBox(height: AppSpacing.xs),
          _SpecTable(item: item),

          const SizedBox(height: AppSpacing.lg),
          const FcLabel('Measured colour'),
          const SizedBox(height: AppSpacing.xs),
          for (final entry in item.effectivePalette)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: colorFromHex(entry.hex),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                          color: colors.swatchBorder(colorFromHex(entry.hex))),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(entry.hex.toUpperCase(),
                      style: AppTypography.monoValue(colors.onSurface, size: 13)),
                  const Spacer(),
                  Text('${(entry.weight * 100).round()}%',
                      style: AppTypography.mono(colors.onSurfaceMuted)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    WardrobeViewModel wardrobe,
    WardrobeItem item,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove this ${item.category.label.toLowerCase()}?'),
        // Says what actually happens, including the part the user cannot see: outfits keep working.
        content: const Text(
          'It leaves your wardrobe and stops appearing in outfit suggestions. Outfits you have '
          'already saved keep showing it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Keep it'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.of(context).danger,
            ),
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await wardrobe.deleteItem(item.id);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

class _SpecTable extends StatelessWidget {
  const _SpecTable({required this.item});

  final WardrobeItem item;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final rows = <(String, String)>[
      ('Category', item.category.label),
      ('Occasion', item.occasion.label),
      ('Pattern', item.pattern.label),
      ('Season', item.season.label),
      ('Fit', item.fit.label),
      if (item.fabric?.isNotEmpty == true) ('Fabric', item.fabric!),
      if (item.sleeveType != null) ('Sleeves', item.sleeveType!.label),
      if (item.neckline != null) ('Neckline', item.neckline!.label),
      if (item.secondaryColor?.isNotEmpty == true)
        ('Second colour', item.secondaryColor!),
      ('Slot', item.slot.label),
    ];

    return Column(
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 116,
                  child: Text(label.toUpperCase(),
                      style: AppTypography.mono(colors.onSurfaceMuted)),
                ),
                Expanded(
                  child: Text(value,
                      style: Theme.of(context).textTheme.bodyLarge),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
