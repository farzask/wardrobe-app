import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/thumbnail_resolver.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/vocabulary/fc_vocabulary.dart';
import '../../../core/widgets/fc_widgets.dart';
import '../../../core/widgets/palette_stripe.dart';
import '../models/wardrobe_item.dart';
import '../viewmodels/add_item_viewmodel.dart';
import '../viewmodels/wardrobe_viewmodel.dart';

/// Review and correct what the extractor read (PRD §4.2).
///
/// PRD §8 makes this screen the retention risk for the whole app, so three rules drive its design:
///
/// 1. **Least-confident fields sort to the top.** The user fixes what is probably wrong, not what
///    happens to sort alphabetically.
/// 2. **Every value is a closed vocabulary**, picked from a sheet. Free text here would silently
///    corrupt the compatibility rules, which match on exact values.
/// 3. **Save is never blocked.** An incomplete item beats an abandoned one.
class AttributeReviewView extends StatelessWidget {
  const AttributeReviewView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AddItemViewModel>();
    final item = vm.draft;
    if (item == null) return const SizedBox.shrink();

    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final resolver = context.watch<ThumbnailResolver>();
    final lowConfidence = vm.reviewOrder.where(vm.isLowConfidence).toList();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.md,
              AppSpacing.gutter,
              AppSpacing.lg,
            ),
            children: [
              _Header(item: item, thumbnailUrl: resolver.urlFor(item.thumbnailPath)),
              const SizedBox(height: AppSpacing.lg),

              if (lowConfidence.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken,
                    borderRadius: AppRadius.cardRadius,
                    border: Border.all(color: colors.outline),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.priority_high, size: 16, color: colors.onSurface),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          lowConfidence.length == 1
                              ? 'One of these was a guess. It is first in the list.'
                              : '${lowConfidence.length} of these were guesses. '
                                  'They are at the top.',
                          style: text.bodyMedium?.copyWith(color: colors.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              for (final field in vm.reviewOrder)
                _AttributeRow(
                  field: field,
                  item: item,
                  vm: vm,
                ),

              const SizedBox(height: AppSpacing.lg),
              _MeasuredColour(item: item),
            ],
          ),
        ),
        _SaveBar(vm: vm),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item, required this.thumbnailUrl});

  final WardrobeItem item;
  final String? thumbnailUrl;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: AppRadius.cardRadius,
          child: SizedBox(
            width: 96,
            height: 120,
            child: Row(
              children: [
                PaletteStripe(palette: item.effectivePalette, thickness: 8),
                Expanded(
                  child: thumbnailUrl == null
                      ? ColoredBox(
                          color: colors.surfaceSunken,
                          child: Icon(Icons.checkroom_outlined,
                              color: colors.onSurfaceMuted),
                        )
                      : Image.network(thumbnailUrl!, fit: BoxFit.cover),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${item.primaryColor} ${item.category.label}'.trim(),
                  style: text.titleLarge),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Change anything FitCheck got wrong. Everything here is a tap.',
                style: text.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One attribute: label on the left, current value as a tappable chip on the right.
class _AttributeRow extends StatelessWidget {
  const _AttributeRow({required this.field, required this.item, required this.vm});

  final String field;
  final WardrobeItem item;
  final AddItemViewModel vm;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final corrected = vm.correctedFields.contains(field);
    final uncertain = vm.isLowConfidence(field);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(
              _labelFor(field),
              style: AppTypography.mono(colors.onSurfaceMuted),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FcChip(
                label: _valueLabel(context, field, item),
                // The dot marks a field the extractor was unsure about — and stops marking it once
                // the user has settled it.
                marked: uncertain && !corrected,
                onTap: () => _pick(context, field),
              ),
            ),
          ),
          if (corrected)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xs),
              child: Icon(Icons.check, size: 16, color: colors.onSurfaceMuted),
            ),
        ],
      ),
    );
  }

  static String _labelFor(String field) => switch (field) {
        'category' => 'Category',
        'occasion' => 'Occasion',
        'pattern' => 'Pattern',
        'season' => 'Season',
        'fit' => 'Fit',
        'style' => 'Style',
        'fabric' => 'Fabric',
        'sleeve_type' => 'Sleeves',
        'neckline' => 'Neckline',
        _ => field,
      };

  static String _valueLabel(BuildContext context, String field, WardrobeItem item) =>
      switch (field) {
        'category' => item.category.label,
        'occasion' => item.occasion.label,
        'pattern' => item.pattern.label,
        'season' => item.season.label,
        'fit' => item.fit.label,
        'style' => item.style?.isNotEmpty == true ? item.style! : 'Not set',
        'fabric' => item.fabric?.isNotEmpty == true ? item.fabric! : 'Not set',
        // "None" is a real answer distinct from "unknown": a sleeveless top genuinely has no
        // sleeve type, and the user must be able to say so.
        'sleeve_type' => item.sleeveType?.label ?? 'None',
        'neckline' => item.neckline?.label ?? 'None',
        _ => '—',
      };

  void _pick(BuildContext context, String field) {
    // `style` and `fabric` are the only open-ended attributes — no compatibility rule reads them,
    // so free text there cannot corrupt scoring.
    if (field == 'style' || field == 'fabric') {
      _editText(context, field);
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final options = _optionsFor(field);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              0,
              AppSpacing.gutter,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_labelFor(field),
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final (label, apply) in options)
                      FcChip(
                        label: label,
                        selected: label == _valueLabel(context, field, item),
                        onTap: () {
                          vm.edit(apply, field);
                          Navigator.of(sheetContext).pop();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<(String, WardrobeItem Function(WardrobeItem))> _optionsFor(String field) {
    return switch (field) {
      'category' => [
          for (final v in FcCategory.values) (v.label, (i) => i.copyWith(category: v))
        ],
      'occasion' => [
          for (final v in FcOccasion.values) (v.label, (i) => i.copyWith(occasion: v))
        ],
      'pattern' => [
          for (final v in FcPattern.values) (v.label, (i) => i.copyWith(pattern: v))
        ],
      'season' => [
          for (final v in FcSeason.values) (v.label, (i) => i.copyWith(season: v))
        ],
      'fit' => [for (final v in FcFit.values) (v.label, (i) => i.copyWith(fit: v))],
      'sleeve_type' => [
          ('None', (i) => i.copyWith(clearSleeveType: true)),
          for (final v in FcSleeveType.values) (v.label, (i) => i.copyWith(sleeveType: v)),
        ],
      'neckline' => [
          ('None', (i) => i.copyWith(clearNeckline: true)),
          for (final v in FcNeckline.values) (v.label, (i) => i.copyWith(neckline: v)),
        ],
      _ => const [],
    };
  }

  void _editText(BuildContext context, String field) {
    final controller = TextEditingController(
      text: field == 'style' ? item.style : item.fabric,
    );
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_labelFor(field)),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.none,
          decoration: InputDecoration(
            hintText: field == 'style' ? 'button-down, polo, A-line…' : 'cotton, denim, silk…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              vm.edit(
                (i) => field == 'style'
                    ? i.copyWith(style: value)
                    : i.copyWith(fabric: value),
                field,
              );
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// The measured palette, shown read-only.
///
/// Read-only because it is measured from the garment's pixels, not guessed — there is nothing for
/// the user to correct. Showing the hex values in mono makes that legible as data rather than as an
/// opinion the app is offering.
class _MeasuredColour extends StatelessWidget {
  const _MeasuredColour({required this.item});

  final WardrobeItem item;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FcLabel('Measured colour'),
        const SizedBox(height: AppSpacing.xs),
        for (final entry in item.effectivePalette)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: colorFromHex(entry.hex),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: colors.swatchBorder(colorFromHex(entry.hex)),
                    ),
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
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.vm});

  final AddItemViewModel vm;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outline)),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.all(AppSpacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (vm.errorMessage != null && vm.stage == AddItemStage.review) ...[
              Text(
                vm.errorMessage!,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: colors.danger),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            FilledButton(
              // Never disabled on completeness. An item saved with one wrong field is worth far
              // more than an item the user gave up on.
              onPressed: vm.stage == AddItemStage.saving
                  ? null
                  : () async {
                      final saved = await vm.save();
                      if (saved != null && context.mounted) {
                        context.read<WardrobeViewModel>().insert(saved);
                        Navigator.of(context).pop(true);
                      }
                    },
              child: vm.stage == AddItemStage.saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Add to wardrobe'),
            ),
          ],
        ),
      ),
    );
  }
}
