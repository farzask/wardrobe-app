import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/thumbnail_resolver.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/vocabulary/colour_family.dart';
import '../../../core/vocabulary/fc_vocabulary.dart';
import '../../../core/widgets/fc_widgets.dart';
import '../../../core/widgets/item_card.dart';
import '../../auth/viewmodels/auth_viewmodel.dart';
import '../../outfit/views/outfit_builder_view.dart';
import '../viewmodels/wardrobe_viewmodel.dart';
import 'add_item_view.dart';
import 'item_detail_view.dart';

/// The wardrobe grid — a wall of the user's own colours.
///
/// Every one of the states in `skills/ui-ux-design/SKILL.md` §3 is reachable here: empty,
/// loading, loaded, offline-from-cache, filtered-empty, and error.
class WardrobeHomeView extends StatefulWidget {
  const WardrobeHomeView({super.key});

  @override
  State<WardrobeHomeView> createState() => _WardrobeHomeViewState();
}

class _WardrobeHomeViewState extends State<WardrobeHomeView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WardrobeViewModel>().load();
    });
  }

  Future<void> _openAddItem() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddItemView()),
    );
    if (added == true && mounted) {
      await context.read<WardrobeViewModel>().load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wardrobe = context.watch<WardrobeViewModel>();
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wardrobe'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: wardrobe.filters.isActive,
              label: Text('${wardrobe.filters.count}'),
              child: const Icon(Icons.tune),
            ),
            tooltip: 'Filter wardrobe',
            onPressed: wardrobe.totalCount == 0 ? null : () => _openFilters(context),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => context.read<AuthViewModel>().signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (wardrobe.status == WardrobeStatus.offlineCache)
            FcOfflineBanner(cachedAt: wardrobe.cachedAt),
          Expanded(child: _body(context, wardrobe)),
        ],
      ),
      bottomNavigationBar: wardrobe.totalCount >= 2
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                0,
                AppSpacing.gutter,
                AppSpacing.sm,
              ),
              child: FilledButton.icon(
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('Check an outfit'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const OutfitBuilderView()),
                ),
              ),
            )
          : null,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddItem,
        backgroundColor: colors.onSurface,
        foregroundColor: colors.surface,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: Text('Add item', style: text.labelLarge?.copyWith(color: colors.surface)),
      ),
    );
  }

  Widget _body(BuildContext context, WardrobeViewModel wardrobe) {
    switch (wardrobe.status) {
      case WardrobeStatus.loading:
        return const Center(child: CircularProgressIndicator());

      case WardrobeStatus.error:
        return FcNotice(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load your wardrobe',
          body: wardrobe.errorMessage ?? 'Check your connection and try again.',
          actionLabel: 'Try again',
          onAction: wardrobe.load,
        );

      case WardrobeStatus.empty:
        // First-run. Offers the only action that makes sense — not "clear filters", which a user
        // who has never opened the filter sheet would find baffling.
        return const FcNotice(
          icon: Icons.checkroom_outlined,
          title: 'Nothing in here yet',
          body: 'Photograph a piece of clothing and FitCheck will read its colour, pattern and '
              'fabric, then keep the details instead of the photo.',
        );

      case WardrobeStatus.emptyAfterFilter:
        return FcNotice(
          icon: Icons.filter_alt_off_outlined,
          title: 'Nothing matches those filters',
          body: 'You own ${wardrobe.totalCount} items, but none in this combination.',
          actionLabel: 'Clear filters',
          onAction: wardrobe.clearFilters,
        );

      case WardrobeStatus.loaded:
      case WardrobeStatus.offlineCache:
        return _grid(context, wardrobe);
    }
  }

  Widget _grid(BuildContext context, WardrobeViewModel wardrobe) {
    final resolver = context.watch<ThumbnailResolver>();
    final items = wardrobe.items;

    return RefreshIndicator(
      onRefresh: wardrobe.load,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.sm,
          AppSpacing.gutter,
          // Clears the FAB and the bottom bar; without it the last row is permanently unreachable.
          120,
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
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ItemDetailView(itemId: item.id)),
            ),
          );
        },
      ),
    );
  }

  void _openFilters(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<WardrobeViewModel>(),
        child: const _FilterSheet(),
      ),
    );
  }
}

class _FilterSheet extends StatelessWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context) {
    final wardrobe = context.watch<WardrobeViewModel>();
    final filters = wardrobe.filters;
    final text = Theme.of(context).textTheme;

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
            Row(
              children: [
                Expanded(child: Text('Filter', style: text.titleLarge)),
                if (filters.isActive)
                  TextButton(
                    onPressed: () {
                      wardrobe.clearFilters();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Clear all'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Only categories the user actually owns. Showing all 23 makes them hunt through
            // options that would return nothing.
            _FilterGroup(
              label: 'Category',
              children: [
                for (final category in wardrobe.ownedCategories)
                  FcChip(
                    label: category.label,
                    selected: filters.category == category,
                    onTap: () => wardrobe.applyFilters(
                      filters.category == category
                          ? filters.copyWith(clearCategory: true)
                          : filters.copyWith(category: category),
                    ),
                  ),
              ],
            ),
            // Colour chips carry their own swatch: picking a colour by seeing it beats picking it
            // by reading the word "green".
            _FilterGroup(
              label: 'Colour',
              children: [
                for (final family in wardrobe.ownedColours)
                  _ColourChip(
                    family: family,
                    selected: filters.colour == family,
                    onTap: () => wardrobe.applyFilters(
                      filters.colour == family
                          ? filters.copyWith(clearColour: true)
                          : filters.copyWith(colour: family),
                    ),
                  ),
              ],
            ),
            _FilterGroup(
              label: 'Occasion',
              children: [
                for (final occasion in FcOccasion.values)
                  FcChip(
                    label: occasion.label,
                    selected: filters.occasion == occasion,
                    onTap: () => wardrobe.applyFilters(
                      filters.occasion == occasion
                          ? filters.copyWith(clearOccasion: true)
                          : filters.copyWith(occasion: occasion),
                    ),
                  ),
              ],
            ),
            _FilterGroup(
              label: 'Season',
              children: [
                for (final season in FcSeason.values)
                  FcChip(
                    label: season.label,
                    selected: filters.season == season,
                    onTap: () => wardrobe.applyFilters(
                      filters.season == season
                          ? filters.copyWith(clearSeason: true)
                          : filters.copyWith(season: season),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: AppSpacing.md),
            Text(
              '${wardrobe.items.length} OF ${wardrobe.totalCount} ITEMS',
              style: AppTypography.mono(AppColors.of(context).onSurfaceMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A colour filter chip carrying its own swatch.
///
/// The swatch always gets a border: without one the "black, white & grey" chip's pale end is
/// invisible on a light surface, and that is the most-used filter in most wardrobes.
class _ColourChip extends StatelessWidget {
  const _ColourChip({
    required this.family,
    required this.selected,
    required this.onTap,
  });

  final FcColourFamily family;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: family.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: selected ? colors.onSurface : colors.surfaceRaised,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? colors.onSurface : colors.outline,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: family.swatch,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.swatchBorder(family.swatch)),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  family.label,
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

class _FilterGroup extends StatelessWidget {
  const _FilterGroup({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FcLabel(label),
          const SizedBox(height: AppSpacing.xs),
          Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: children),
        ],
      ),
    );
  }
}
