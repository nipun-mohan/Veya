import 'package:flutter/material.dart';

class VeyaColors {
  static const ink = Color(0xFF1B0734),
      teal = Color(0xFF30105A),
      muted = Color(0xFF64708B),
      paper = Color(0xFFFFFAF3),
      line = Color(0xFFE9E3E8),
      lime = Color(0xFFFFB32B),
      soft = Color(0xFFFFE5D0),
      peach = Color(0xFFFFF0E3),
      mango = Color(0xFFFF9D1B),
      orange = Color(0xFFFF642A),
      lavender = Color(0xFFC98DFF);
}

ThemeData veyaTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: VeyaColors.orange,
        brightness: Brightness.light,
      ).copyWith(
        primary: VeyaColors.ink,
        onPrimary: Colors.white,
        secondary: VeyaColors.orange,
        surface: VeyaColors.paper,
        onSurface: VeyaColors.ink,
        outline: VeyaColors.line,
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Manrope',
    scaffoldBackgroundColor: VeyaColors.paper,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 39,
        fontWeight: FontWeight.w800,
        letterSpacing: -2.1,
        height: 1.03,
      ),
      headlineMedium: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.5,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -.5,
      ),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(fontSize: 16, height: 1.6),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: VeyaColors.paper,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 54),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 50),
        side: const BorderSide(color: VeyaColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: VeyaColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: VeyaColors.line),
      ),
    ),
    dividerTheme: const DividerThemeData(color: VeyaColors.line, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: VeyaColors.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: VeyaColors.paper,
      showDragHandle: true,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: VeyaColors.peach,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
  );
}
