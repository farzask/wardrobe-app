import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../viewmodels/auth_viewmodel.dart';

/// Sign in and sign up, as one screen with a mode toggle.
///
/// Two screens with near-identical fields is a common split that makes the user navigate to find
/// the form they already had in front of them. The only real difference is which button they press.
class SignInView extends StatefulWidget {
  const SignInView({super.key});

  @override
  State<SignInView> createState() => _SignInViewState();
}

class _SignInViewState extends State<SignInView> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isSignUp = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthViewModel>();
    if (_isSignUp) {
      await auth.signUp(email: _email.text.trim(), password: _password.text);
    } else {
      await auth.signIn(email: _email.text.trim(), password: _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('FitCheck', style: text.displayLarge),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Your wardrobe, as data. Then a straight answer about what goes together.',
                      style: text.bodyLarge?.copyWith(color: colors.onSurfaceMuted),
                    ),
                    const SizedBox(height: AppSpacing.xxl),

                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) return 'Enter your email address';
                        if (!v.contains('@') || !v.contains('.')) {
                          return 'That does not look like an email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),

                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: [
                        _isSignUp ? AutofillHints.newPassword : AutofillHints.password
                      ],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (value) {
                        if ((value ?? '').isEmpty) return 'Enter a password';
                        // Only enforced on sign-up: rejecting an existing short password at sign-in
                        // locks people out of their own accounts.
                        if (_isSignUp && value!.length < 8) {
                          return 'Use at least 8 characters';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _submit(),
                    ),

                    if (auth.errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline, size: 16, color: colors.danger),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              auth.errorMessage!,
                              style: text.bodyMedium?.copyWith(color: colors.danger),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: auth.busy ? null : _submit,
                      child: auth.busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isSignUp ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      onPressed: auth.busy
                          ? null
                          : () => setState(() => _isSignUp = !_isSignUp),
                      child: Text(
                        _isSignUp
                            ? 'Already have an account? Sign in'
                            : 'New here? Create an account',
                      ),
                    ),

                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Your wardrobe is private to your account.',
                      textAlign: TextAlign.center,
                      style: AppTypography.mono(colors.onSurfaceMuted, size: 10),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
