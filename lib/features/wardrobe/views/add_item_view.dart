import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/fc_widgets.dart';
import '../viewmodels/add_item_viewmodel.dart';
import 'attribute_review_view.dart';

/// Capture → extract → review (PRD §4.2, TRD §4).
class AddItemView extends StatelessWidget {
  const AddItemView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AddItemViewModel>();

    return PopScope(
      // Backing out of review has to delete the pending row, or it becomes a permanent invisible
      // orphan holding a thumbnail.
      canPop: vm.stage != AddItemStage.review,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard(context, vm);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(switch (vm.stage) {
            AddItemStage.review => 'Check the details',
            _ => 'Add an item',
          }),
        ),
        body: SafeArea(child: _body(context, vm)),
      ),
    );
  }

  Widget _body(BuildContext context, AddItemViewModel vm) {
    switch (vm.stage) {
      case AddItemStage.idle:
        return const _CaptureChoice();

      case AddItemStage.capturing:
      case AddItemStage.uploading:
        return _Working(
          message: vm.stage == AddItemStage.capturing
              ? 'Opening the camera…'
              : 'Reading the garment…',
          detail: vm.stage == AddItemStage.uploading
              ? 'Colour, pattern, fabric and cut. This usually takes a few seconds.'
              : null,
        );

      case AddItemStage.failed:
        return FcNotice(
          icon: Icons.image_not_supported_outlined,
          title: vm.errorRetryable ? 'That did not work' : 'Cannot read that photo',
          body: vm.errorMessage ?? 'Try again.',
          actionLabel: vm.errorRetryable ? 'Try again' : 'Pick another photo',
          onAction: vm.reset,
        );

      case AddItemStage.review:
      case AddItemStage.saving:
      case AddItemStage.done:
        return const AttributeReviewView();
    }
  }

  void _confirmDiscard(BuildContext context, AddItemViewModel vm) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard this item?'),
        content: const Text(
          'The details FitCheck read will not be saved, and the thumbnail is deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Keep editing'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.of(context).danger,
            ),
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await vm.discard();
              if (context.mounted) Navigator.of(context).pop(false);
            },
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }
}

class _CaptureChoice extends StatelessWidget {
  const _CaptureChoice();

  @override
  Widget build(BuildContext context) {
    final vm = context.read<AddItemViewModel>();
    final text = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Photograph one garment', style: text.displayMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'One item at a time, laid flat or on a hanger. A plain background gives the most '
            'accurate colour.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.xl),

          FilledButton.icon(
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Take a photo'),
            onPressed: () => vm.captureAndExtract(fromCamera: true),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Choose from library'),
            onPressed: () => vm.captureAndExtract(fromCamera: false),
          ),

          const SizedBox(height: AppSpacing.xl),
          // Shown here, at the moment the user decides to send a photo — not buried in a settings
          // screen. Required copy; see decision #5 in skills/README.md.
          const FcPrivacyNote(),
        ],
      ),
    );
  }
}

class _Working extends StatelessWidget {
  const _Working({required this.message, this.detail});

  final String message;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.lg),
            Text(message, style: text.titleMedium, textAlign: TextAlign.center),
            if (detail != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(detail!, style: text.bodyMedium, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
