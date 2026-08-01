import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Light and dark are built from the same token set in the same function, so adding a colour to
/// one without the other is not possible by construction.
abstract final class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(AppColors.light, Brightness.light);
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppPalette palette, Brightness brightness) {
    final text = AppTypography.textTheme(palette.onSurface, palette.onSurfaceMuted);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: palette.surface,
      canvasColor: palette.surface,
      extensions: <ThemeExtension<dynamic>>[palette],
      textTheme: text,

      // Achromatic by design — see the rule at the top of app_colors.dart. The seed is a true
      // neutral so Material's generated roles cannot introduce a tint of their own.
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6B6B6B),
        brightness: brightness,
      ).copyWith(
        surface: palette.surface,
        onSurface: palette.onSurface,
        primary: palette.onSurface,
        onPrimary: palette.surface,
        error: palette.danger,
        onError: palette.onDanger,
        outline: palette.outline,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: palette.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),

      dividerTheme: DividerThemeData(
        color: palette.outline,
        thickness: 1,
        space: 1,
      ),

      // Filled, square-ish, high contrast. The primary action is the darkest thing on the screen,
      // which in an achromatic system is the only way to make it unmistakably primary.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.onSurface,
          foregroundColor: palette.surface,
          disabledBackgroundColor: palette.outline,
          disabledForegroundColor: palette.onSurfaceMuted,
          minimumSize: const Size.fromHeight(AppSpacing.minTapTarget),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
          textStyle: text.labelLarge,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.onSurface,
          side: BorderSide(color: palette.outlineStrong, width: 1.5),
          minimumSize: const Size.fromHeight(AppSpacing.minTapTarget),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
          textStyle: text.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.onSurface,
          minimumSize: const Size(AppSpacing.minTapTarget, AppSpacing.minTapTarget),
          textStyle: text.labelLarge,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceSunken,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.cardRadius,
          borderSide: BorderSide(color: palette.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.cardRadius,
          borderSide: BorderSide(color: palette.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.cardRadius,
          borderSide: BorderSide(color: palette.outlineStrong, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.cardRadius,
          borderSide: BorderSide(color: palette.danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.cardRadius,
          borderSide: BorderSide(color: palette.danger, width: 2),
        ),
        labelStyle: AppTypography.mono(palette.onSurfaceMuted),
        floatingLabelStyle: AppTypography.mono(palette.onSurface),
        errorStyle: TextStyle(color: palette.danger, fontSize: 13),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
        showDragHandle: true,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.onSurface,
        contentTextStyle: TextStyle(color: palette.surface, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.onSurface,
        linearTrackColor: palette.outline,
        circularTrackColor: palette.outline,
      ),
    );
  }
}
