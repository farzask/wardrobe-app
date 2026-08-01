import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/thumbnail_resolver.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/fc_widgets.dart';
import '../../../core/widgets/item_card.dart';
import '../../../core/widgets/palette_stripe.dart';
import '../../wardrobe/viewmodels/wardrobe_viewmodel.dart';
import '../viewmodels/outfit_viewmodel.dart';
import 'outfit_result_view.dart';

/// Pick items from the wardrobe to form an outfit (PRD §4.4a).
class OutfitBuilderView extends StatelessWidget {
  const OutfitBuilderView({super.key});

  @override
  Widget build(BuildContext context) {
    final outfit = context.watch<OutfitViewModel>();
    final wardrobe = context.watch<WardrobeViewModel>();
    final resolver = context.watch<ThumbnailResolver>();
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final items = wardrobe.items;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Build an outfit'),
        actions: [
          if (outfit.selected.isNotEmpty)
            TextButton(onPressed: outfit.clear, child: const Text('Clear')),
        ],
      ),
      body: Column(
        children: [
          if (outfit.stage == OutfitStage.offlineBlocked)
            Container(
              width: double.infinity,
              color: colors.surfaceSunken,
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: [
                  Icon(Icons.cloud_off_outlined, size: 16, color: colors.onSurface),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Checking an outfit needs a connection. Browsing works offline.',
                      style: text.bodyMedium?.copyWith(color: colors.onSurface),
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: items.isEmpty
                ? const FcNotice(
                    icon: Icons.checkroom_outlined,
                    title: 'Add a few items first',
                    body: 'FitCheck needs at least two garments to compare.',
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      AppSpacing.sm,
                      AppSpacing.gutter,
                      AppSpacing.sm,
                    ),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200,
                      mainAxisSpacing: AppSpacing.sm,
                      crossAxisSpacing: AppSpacing.sm,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ItemCard(
                        item: item,
                        thumbnailUrl: resolver.urlFor(item.thumbnailPath),
                        selected: outfit.isSelected(item.id),
                        onTap: () => outfit.toggle(item),
                      );
                    },
                  ),
          ),

          _SelectionBar(outfit: outfit),
        ],
      ),
    );
  }
}

/// The current outfit, as a slot summary plus its combined colour band.
///
/// The band is the point: it is literally what the compatibility engine scores, so a clash is
/// visible here before the user has pressed anything.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.outfit});

  final OutfitViewModel outfit;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final selected = outfit.selected;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outline)),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.all(AppSpacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (selected.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  'Tap items to put them in the outfit.',
                  style: text.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              )
            else ...[
              OutfitPaletteBand(items: selected),
              const SizedBox(height: AppSpacing.xs),
              Text(
                selected.map((i) => i.slot.label).toSet().join(' · ').toUpperCase(),
                style: AppTypography.mono(colors.onSurfaceMuted),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],

            FilledButton(
              onPressed: outfit.canEvaluate && outfit.stage != OutfitStage.evaluating
                  ? () async {
                      await outfit.evaluate();
                      if (context.mounted && outfit.stage == OutfitStage.result) {
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const OutfitResultView()),
                        );
                      }
                    }
                  : null,
              child: outfit.stage == OutfitStage.evaluating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      selected.length < 2
                          ? 'Pick at least 2 items'
                          : 'Check this outfit',
                    ),
            ),

            if (outfit.stage == OutfitStage.failed && outfit.errorMessage != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                outfit.errorMessage!,
                style: text.bodyMedium?.copyWith(color: colors.danger),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
