import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// A small tracked-mono label. The utility voice of the app.
class FcLabel extends StatelessWidget {
  const FcLabel(this.text, {super.key, this.muted = true});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Text(
      text.toUpperCase(),
      style: AppTypography.mono(muted ? colors.onSurfaceMuted : colors.onSurface),
    );
  }
}

/// A tappable attribute value. Used throughout the review screen and the filter sheet.
class FcChip extends StatelessWidget {
  const FcChip({
    super.key,
    required this.label,
    this.onTap,
    this.selected = false,
    this.marked = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool selected;

  /// Draws attention without using colour — a filled dot before the label. Used for
  /// low-confidence fields on the review screen.
  final bool marked;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      button: onTap != null,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.chipRadius,
        child: ConstrainedBox(
          // Chips in a dense row are the classic tap-target violation.
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? colors.onSurface : colors.surfaceRaised,
              borderRadius: AppRadius.chipRadius,
              border: Border.all(
                color: selected ? colors.onSurface : colors.outline,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (marked) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: selected ? colors.surface : colors.onSurface,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: selected ? colors.surface : colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty, error and offline states.
///
/// One widget because these three are the screens most often left half-built, and giving them a
/// shared shape makes it obvious when one is missing its action.
class FcNotice extends StatelessWidget {
  const FcNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: colors.onSurfaceMuted),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: text.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xs),
            Text(body, style: text.bodyMedium, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// The offline banner.
///
/// Says when the data is from, not just that the device is offline — "offline" alone leaves the
/// user wondering whether what they are looking at is current.
class FcOfflineBanner extends StatelessWidget {
  const FcOfflineBanner({super.key, required this.cachedAt});

  final DateTime? cachedAt;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      color: colors.surfaceSunken,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 14, color: colors.onSurfaceMuted),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              cachedAt == null
                  ? 'Offline · showing saved wardrobe'
                  : 'Offline · saved ${_ago(cachedAt!)}',
              style: AppTypography.mono(colors.onSurfaceMuted, size: 10),
            ),
          ),
        ],
      ),
    );
  }

  static String _ago(DateTime when) {
    final delta = DateTime.now().difference(when);
    if (delta.inMinutes < 1) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    return '${delta.inDays}d ago';
  }
}

/// The privacy disclosure shown at the capture step.
///
/// Required copy, not optional. Decision #5 put extraction on Gemini's free tier, where Google may
/// retain submitted images and human reviewers may see them. PRD §4.2 was corrected to say so, and
/// this is where the user actually reads it — at the moment they choose to send a photo.
class FcPrivacyNote extends StatelessWidget {
  const FcPrivacyNote({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: colors.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: colors.onSurfaceMuted),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'FitCheck keeps only a thumbnail and the attributes, never your original photo. '
              'The photo is sent to Google Gemini to be read. On the free tier Google may keep it '
              'to improve their products.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
