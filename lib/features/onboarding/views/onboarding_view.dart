import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/vocabulary/fc_vocabulary.dart';
import '../../auth/viewmodels/auth_viewmodel.dart';

/// Gender selection (PRD §4.1).
///
/// Nothing is preselected. A default here is not a convenience — it is the app guessing something
/// personal about the user and making them notice it was wrong.
class GenderSelectView extends StatefulWidget {
  const GenderSelectView({super.key});

  @override
  State<GenderSelectView> createState() => _GenderSelectViewState();
}

class _GenderSelectViewState extends State<GenderSelectView> {
  FcGender? _choice;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xl),
              const _Step(current: 1, total: 2),
              const SizedBox(height: AppSpacing.md),
              Text('Who are we styling?', style: text.displayMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'This decides which styling suggestions FitCheck shows alongside an outfit. '
                'It does not change how your clothes are read or scored.',
                style: text.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.xl),

              for (final gender in FcGender.values) ...[
                _ChoiceTile(
                  label: gender.label,
                  selected: _choice == gender,
                  onTap: () => setState(() => _choice = gender),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],

              const Spacer(),
              FilledButton(
                onPressed: (_choice == null || auth.busy)
                    ? null
                    : () => auth.chooseGender(_choice!),
                child: auth.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The male accessory opt-in (PRD §4.1).
///
/// A "no" here means the accessory recommendation is never produced — not produced and hidden. The
/// gate is enforced on the server from this stored answer.
class AccessoryOptInView extends StatefulWidget {
  const AccessoryOptInView({super.key});

  @override
  State<AccessoryOptInView> createState() => _AccessoryOptInViewState();
}

class _AccessoryOptInViewState extends State<AccessoryOptInView> {
  bool? _choice;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xl),
              const _Step(current: 2, total: 2),
              const SizedBox(height: AppSpacing.md),
              Text('Do you wear accessories?', style: text.displayMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Watches, belts, bracelets, sunglasses. Say no and FitCheck will never suggest '
                'them. You can change this later.',
                style: text.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.xl),

              _ChoiceTile(
                label: 'Yes, suggest accessories',
                selected: _choice == true,
                onTap: () => setState(() => _choice = true),
              ),
              const SizedBox(height: AppSpacing.sm),
              _ChoiceTile(
                label: 'No, skip accessories',
                selected: _choice == false,
                onTap: () => setState(() => _choice = false),
              ),

              const Spacer(),
              FilledButton(
                onPressed: (_choice == null || auth.busy)
                    ? null
                    : () => auth.answerAccessories(_choice!),
                child: auth.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Finish'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    // Numbered because onboarding genuinely is a sequence and the count tells the user how much is
    // left — not as decoration.
    return Text(
      'STEP $current OF $total',
      style: AppTypography.mono(colors.onSurfaceMuted),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardRadius,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            borderRadius: AppRadius.cardRadius,
            border: Border.all(
              color: selected ? colors.outlineStrong : colors.outline,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: Theme.of(context).textTheme.titleMedium),
              ),
              // Selection carried by icon and border weight, not by hue.
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? colors.onSurface : colors.onSurfaceMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
