import 'package:flutter/material.dart';

class VeyaColors {
  static const ink = Color(0xFF173F38),
      teal = Color(0xFF235B4E),
      muted = Color(0xFF73817B),
      paper = Color(0xFFF7F8F2),
      line = Color(0xFFE5E9DF),
      lime = Color(0xFFD9F291),
      soft = Color(0xFFECF1E6),
      peach = Color(0xFFF7E8D9);
}

ThemeData veyaTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: VeyaColors.teal,
        brightness: Brightness.light,
      ).copyWith(
        primary: VeyaColors.teal,
        onPrimary: Colors.white,
        secondary: VeyaColors.lime,
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
        fontSize: 36,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.7,
        height: 1.15,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.1,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: VeyaColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
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
      indicatorColor: VeyaColors.soft,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
  );
}
