import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../features/wardrobe/models/wardrobe_item.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'palette_stripe.dart';

/// A wardrobe item as a specimen card.
///
/// The thumbnail is deliberately NOT the hero. TRD §4.4 caps thumbnails at ~320px and ≤30 KB, cut
/// from photos of wildly varying quality — leaning on them the way a photo-first closet app does
/// would make the grid look broken. So the card leads with the measured colour and the spec, which
/// are consistent and precise, and uses the thumbnail as a secondary identifier.
class ItemCard extends StatelessWidget {
  const ItemCard({
    super.key,
    required this.item,
    required this.thumbnailUrl,
    this.onTap,
    this.selected = false,
    this.flagged = false,
    this.flagLabel,
  });

  final WardrobeItem item;
  final String? thumbnailUrl;
  final VoidCallback? onTap;

  /// In the outfit builder: this item is in the outfit.
  final bool selected;

  /// On the result screen: this is the weak link.
  ///
  /// Marked with a heavy border, an icon, and a text label — never by colour alone. The palette is
  /// achromatic precisely so that meaning cannot leak into hue, and this app's users are
  /// disproportionately likely to care about colour vision.
  final bool flagged;
  final String? flagLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: '${item.primaryColor} ${item.category.label}'
          '${flagged ? ', ${flagLabel ?? 'needs attention'}' : ''}',
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardRadius,
        child: Container(
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            borderRadius: AppRadius.cardRadius,
            border: Border.all(
              color: (selected || flagged) ? colors.outlineStrong : colors.outline,
              width: (selected || flagged) ? 2.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The signature stripe, running the full height of the card's image area.
                    PaletteStripe(palette: item.effectivePalette, thickness: 8),
                    Expanded(child: _Thumbnail(url: thumbnailUrl, item: item)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xs,
                  AppSpacing.xs,
                  AppSpacing.xs,
                  AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.category.label,
                      style: text.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    // The spec line: mono, tracked, uppercase. Reads as a specimen label.
                    Text(
                      [
                        item.primaryColor,
                        item.pattern.label,
                        item.occasion.label,
                      ].join(' · ').toUpperCase(),
                      style: AppTypography.mono(colors.onSurfaceMuted, size: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (flagged) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          Icon(Icons.error_outline,
                              size: 14, color: colors.onSurface),
                          const SizedBox(width: AppSpacing.xxs),
                          Expanded(
                            child: Text(
                              (flagLabel ?? 'Weak link').toUpperCase(),
                              style: AppTypography.mono(colors.onSurface,
                                  size: 10, weight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.url, required this.item});

  final String? url;
  final WardrobeItem item;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    // No thumbnail is a degraded card, not a broken one: the colour block still identifies the
    // item, which is the whole premise of storing attributes instead of photos.
    if (url == null) {
      return ColoredBox(
        color: colors.surfaceSunken,
        child: Center(
          child: Icon(Icons.checkroom_outlined,
              size: 28, color: colors.onSurfaceMuted),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, _) => ColoredBox(color: colors.surfaceSunken),
      errorWidget: (_, _, _) => ColoredBox(
        color: colors.surfaceSunken,
        child: Center(
          child: Icon(Icons.checkroom_outlined,
              size: 28, color: colors.onSurfaceMuted),
        ),
      ),
    );
  }
}
