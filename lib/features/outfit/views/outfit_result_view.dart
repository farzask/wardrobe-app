import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/thumbnail_resolver.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/fc_widgets.dart';
import '../../../core/widgets/item_card.dart';
import '../../../core/widgets/palette_stripe.dart';
import '../../wardrobe/viewmodels/wardrobe_viewmodel.dart';
import '../models/outfit_result.dart';
import '../viewmodels/outfit_viewmodel.dart';

/// The verdict (PRD §4.4, §4.5).
///
/// The score is deliberately NOT the hero. A big number invites arguing with the number; PRD §8
/// says the value of this screen is that the feedback names the right item and the user trusts it.
/// So the verdict sentence leads, the weak item is pointed at in the outfit strip itself, and the
/// score sits alongside as a measurement.
class OutfitResultView extends StatelessWidget {
  const OutfitResultView({super.key});

  @override
  Widget build(BuildContext context) {
    final outfit = context.watch<OutfitViewModel>();
    final result = outfit.result;
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;

    if (result == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const FcNotice(
          icon: Icons.help_outline,
          title: 'Nothing to show',
          body: 'Build an outfit and check it to see a verdict.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Verdict')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.md,
          AppSpacing.gutter,
          AppSpacing.xxl,
        ),
        children: [
          // The outfit's combined colour — what the engine actually scored.
          OutfitPaletteBand(items: outfit.selected, height: 14),
          const SizedBox(height: AppSpacing.lg),

          Text(
            result.isGood ? 'This works.' : 'One thing is off.',
            style: text.displayLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(result.suggestionText, style: text.bodyLarge),

          if (result.completenessWarning != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: colors.onSurfaceMuted),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(result.completenessWarning!, style: text.bodyMedium),
                ),
              ],
            ),
          ],

          const SizedBox(height: AppSpacing.lg),
          _ScoreRow(result: result),

          const SizedBox(height: AppSpacing.lg),
          const FcLabel('The outfit'),
          const SizedBox(height: AppSpacing.xs),
          _OutfitStrip(outfit: outfit, result: result),

          if (result.suggestions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const FcLabel('Try instead'),
            const SizedBox(height: AppSpacing.xs),
            for (final suggestion in result.suggestions)
              _SwapCard(suggestion: suggestion),
          ],

          // Whole card present or absent — never an empty placeholder. Absent for a male user who
          // opted out of accessories (PRD §4.5).
          if (result.recommendations.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _RecommendationCard(recommendations: result.recommendations),
          ],

          const SizedBox(height: AppSpacing.lg),
          OutlinedButton(
            onPressed: () {
              outfit.backToBuilding();
              Navigator.of(context).pop();
            },
            child: const Text('Change the outfit'),
          ),

          const SizedBox(height: AppSpacing.md),
          Text(
            'SCORED BY ${result.rulesetVersion.toUpperCase()}',
            textAlign: TextAlign.center,
            style: AppTypography.mono(colors.onSurfaceMuted, size: 9),
          ),
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({required this.result});

  final OutfitResult result;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: colors.outline),
      ),
      child: Row(
        children: [
          Text(
            '${result.score}',
            style: AppTypography.monoValue(colors.onSurface, size: 30),
          ),
          Text('/100', style: AppTypography.mono(colors.onSurfaceMuted, size: 13)),
          const SizedBox(width: AppSpacing.md),
          // A bar rather than a ring: it sits on the same horizontal axis as the palette band
          // above, so the two read as one measurement of the same thing.
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: LinearProgressIndicator(
                value: result.score / 100,
                minHeight: 8,
                backgroundColor: colors.outline,
                valueColor: AlwaysStoppedAnimation(colors.onSurface),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutfitStrip extends StatelessWidget {
  const _OutfitStrip({required this.outfit, required this.result});

  final OutfitViewModel outfit;
  final OutfitResult result;

  @override
  Widget build(BuildContext context) {
    final resolver = context.watch<ThumbnailResolver>();

    return SizedBox(
      height: 210,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: outfit.selected.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, index) {
          final item = outfit.selected[index];
          final isWeak = item.id == result.weakItemId;
          return SizedBox(
            width: 150,
            // The weak item is marked in the strip itself, not only described in prose. PRD §8
            // says the value is that the feedback names the item — so point at it.
            child: ItemCard(
              item: item,
              thumbnailUrl: resolver.urlFor(item.thumbnailPath),
              flagged: isWeak,
              flagLabel: 'Weak link',
            ),
          );
        },
      ),
    );
  }
}

/// A suggested swap, tappable to re-check.
///
/// Tapping closes the loop the screen opens: select → evaluate → weak link → swap → evaluate again.
class _SwapCard extends StatelessWidget {
  const _SwapCard({required this.suggestion});

  final SwapSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final outfit = context.read<OutfitViewModel>();
    final replacement = context.read<WardrobeViewModel>().byId(
          suggestion.replacementItemId,
        );

    if (replacement == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: InkWell(
        borderRadius: AppRadius.cardRadius,
        onTap: () async {
          await outfit.applySwap(suggestion, replacement);
        },
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            borderRadius: AppRadius.cardRadius,
            border: Border.all(color: colors.outline),
          ),
          child: Row(
            children: [
              PaletteStripe(
                palette: replacement.effectivePalette,
                thickness: 8,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your ${replacement.primaryColor} '
                      '${replacement.category.label.toLowerCase()}',
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Takes this outfit to ${suggestion.newScore}',
                      style: text.bodyMedium,
                    ),
                  ],
                ),
              ),
              Text('+${suggestion.delta}',
                  style: AppTypography.monoValue(colors.onSurface)),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.chevron_right, color: colors.onSurfaceMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.recommendations});

  final List<StyleRecommendation> recommendations;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FcLabel('To finish the look'),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < recommendations.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            Text(recommendations[i].type.label, style: text.titleMedium),
            const SizedBox(height: AppSpacing.xxs),
            Text(recommendations[i].suggestionText, style: text.bodyLarge),
          ],
        ],
      ),
    );
  }
}
