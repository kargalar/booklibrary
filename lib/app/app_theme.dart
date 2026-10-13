import 'package:flutter/material.dart';

ThemeData buildAppTheme(ColorScheme scheme) => ThemeData(
  colorScheme: scheme,
  useMaterial3: true,
  scaffoldBackgroundColor: scheme.surface,
  visualDensity: VisualDensity.standard,
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: scheme.brightness == Brightness.dark
        ? Colors.black
        : scheme.surfaceContainerLow,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: _inputBorder(scheme.outlineVariant),
    enabledBorder: _inputBorder(scheme.outlineVariant),
    focusedBorder: _inputBorder(scheme.primary, width: 1.5),
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    margin: EdgeInsets.zero,
    color: scheme.brightness == Brightness.dark
        ? Colors.black
        : scheme.surfaceContainerLowest,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
  ),
  appBarTheme: const AppBarTheme(
    elevation: 0,
    scrolledUnderElevation: 0,
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
  ),
  navigationBarTheme: NavigationBarThemeData(
    elevation: 0,
    backgroundColor: scheme.brightness == Brightness.dark
        ? Colors.black
        : scheme.surfaceContainerLowest,
    indicatorColor: scheme.primary.withAlpha(28),
    labelTextStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  ),
  chipTheme: ChipThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    side: BorderSide.none,
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
  ),
);

OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color, width: width),
    );
