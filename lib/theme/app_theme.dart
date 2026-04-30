import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static const double _fieldRadius = 14;
  static const double _buttonRadius = 14;
  static const double _cardRadius = 20;

  static const EdgeInsets _fieldPadding =
      EdgeInsets.symmetric(horizontal: 16, vertical: 15);
  static const EdgeInsets _buttonPadding =
      EdgeInsets.symmetric(horizontal: 20, vertical: 0);

  // ── Light input borders ──────────────────────────────────────────────────
  static final _lightInputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_fieldRadius),
    borderSide: const BorderSide(color: AppColors.lightBorderMedium, width: 1),
  );
  static final _lightFocusedInputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_fieldRadius),
    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
  );
  static final _lightErrorInputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_fieldRadius),
    borderSide: const BorderSide(color: AppColors.error, width: 1.2),
  );

  // ── Dark input borders ───────────────────────────────────────────────────
  static final _darkInputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_fieldRadius),
    borderSide: const BorderSide(color: AppColors.darkBorderStrong, width: 1),
  );
  static final _darkFocusedInputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_fieldRadius),
    borderSide: const BorderSide(color: AppColors.primaryLight, width: 1.5),
  );
  static final _darkErrorInputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_fieldRadius),
    borderSide: const BorderSide(color: AppColors.error, width: 1.2),
  );

  // ══════════════════════════════════════════════════════════════════════════
  // LIGHT THEME
  // ══════════════════════════════════════════════════════════════════════════
  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    primaryColor: AppColors.primary,
    scaffoldBackgroundColor: AppColors.lightBackground,
    splashFactory: InkRipple.splashFactory,
    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      error: AppColors.error,
      onError: Colors.white,
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightTextPrimary,
      tertiary: AppColors.accent,
      onTertiary: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.lightSurface,
      foregroundColor: AppColors.lightTextPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      toolbarHeight: 54,
      titleTextStyle: TextStyle(
        color: AppColors.lightTextPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.lightSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
        side: const BorderSide(color: AppColors.lightBorderMedium),
      ),
    ),
    dividerColor: AppColors.lightBorderSoft,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.lightSurface,
      contentPadding: _fieldPadding,
      isDense: true,
      hintStyle: TextStyle(
        color: AppColors.lightTextSecondary.withOpacity(.65),
        fontWeight: FontWeight.w400,
        fontSize: 15,
      ),
      labelStyle: const TextStyle(
        color: AppColors.lightTextPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 14.5,
      ),
      floatingLabelStyle: const TextStyle(
        color: AppColors.primary,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
      enabledBorder: _lightInputBorder,
      focusedBorder: _lightFocusedInputBorder,
      errorBorder: _lightErrorInputBorder,
      focusedErrorBorder: _lightErrorInputBorder,
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: const BorderSide(color: AppColors.lightBorderSoft),
      ),
      border: _lightInputBorder,
      errorStyle: const TextStyle(
        color: AppColors.error,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
      ),
      prefixIconColor: AppColors.lightTextSecondary,
      suffixIconColor: AppColors.lightTextSecondary,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.lightBorderMedium,
        disabledForegroundColor: Colors.white54,
        minimumSize: const Size(0, 48),
        padding: _buttonPadding,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shadowColor: AppColors.primary.withOpacity(0.30),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_buttonRadius),
        ),
        textStyle: const TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
          height: 1.1,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.secondary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.lightBorderMedium,
        disabledForegroundColor: Colors.white54,
        minimumSize: const Size(0, 48),
        padding: _buttonPadding,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_buttonRadius),
        ),
        textStyle: const TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
          height: 1.1,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        disabledForegroundColor: AppColors.lightTextSecondary,
        minimumSize: const Size(0, 48),
        padding: _buttonPadding,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: const BorderSide(color: AppColors.primary, width: 1.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_buttonRadius),
        ),
        textStyle: const TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
          height: 1.1,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_buttonRadius),
        ),
        textStyle: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
          height: 1.1,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(38, 38),
        maximumSize: const Size(38, 38),
        padding: const EdgeInsets.all(8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.primary;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: const BorderSide(color: AppColors.lightBorderStrong, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.primaryDark,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w500,
        fontSize: 13.5,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 6,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );

  // ══════════════════════════════════════════════════════════════════════════
  // DARK THEME
  // ══════════════════════════════════════════════════════════════════════════
  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    primaryColor: AppColors.primary,
    scaffoldBackgroundColor: AppColors.darkBackground,
    splashFactory: InkRipple.splashFactory,
    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.primaryLight,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: AppColors.darkBackground,
      error: AppColors.error,
      onError: Colors.white,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkTextPrimary,
      tertiary: AppColors.accent,
      onTertiary: AppColors.darkBackground,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkSurface,
      foregroundColor: AppColors.darkTextPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      toolbarHeight: 54,
      titleTextStyle: TextStyle(
        color: AppColors.darkTextPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.darkSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
        side: const BorderSide(color: AppColors.darkBorderMedium),
      ),
    ),
    dividerColor: AppColors.darkBorderSoft,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkSurface,
      contentPadding: _fieldPadding,
      isDense: true,
      hintStyle: TextStyle(
        color: AppColors.darkTextSecondary.withOpacity(.65),
        fontWeight: FontWeight.w400,
        fontSize: 15,
      ),
      labelStyle: const TextStyle(
        color: AppColors.darkTextPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 14.5,
      ),
      floatingLabelStyle: const TextStyle(
        color: AppColors.primaryLight,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
      enabledBorder: _darkInputBorder,
      focusedBorder: _darkFocusedInputBorder,
      errorBorder: _darkErrorInputBorder,
      focusedErrorBorder: _darkErrorInputBorder,
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: const BorderSide(color: AppColors.darkBorderSoft),
      ),
      border: _darkInputBorder,
      errorStyle: const TextStyle(
        color: AppColors.error,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
      ),
      prefixIconColor: AppColors.darkTextSecondary,
      suffixIconColor: AppColors.darkTextSecondary,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.darkBorderMedium,
        disabledForegroundColor: Colors.white38,
        minimumSize: const Size(0, 48),
        padding: _buttonPadding,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_buttonRadius),
        ),
        textStyle: const TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
          height: 1.1,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.secondary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.darkBorderMedium,
        disabledForegroundColor: Colors.white38,
        minimumSize: const Size(0, 48),
        padding: _buttonPadding,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_buttonRadius),
        ),
        textStyle: const TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
          height: 1.1,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryLight,
        disabledForegroundColor: AppColors.darkTextSecondary,
        minimumSize: const Size(0, 48),
        padding: _buttonPadding,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: const BorderSide(color: AppColors.primaryLight, width: 1.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_buttonRadius),
        ),
        textStyle: const TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
          height: 1.1,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primaryLight,
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_buttonRadius),
        ),
        textStyle: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
          height: 1.1,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(38, 38),
        maximumSize: const Size(38, 38),
        padding: const EdgeInsets.all(8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.primaryLight;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: const BorderSide(color: AppColors.darkBorderStrong, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.darkSurface3,
      contentTextStyle: const TextStyle(
        color: AppColors.darkTextPrimary,
        fontWeight: FontWeight.w500,
        fontSize: 13.5,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 6,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
