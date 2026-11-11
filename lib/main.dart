import 'package:flutter/material.dart';

import 'ui/audit_page.dart';

void main() => runApp(const RoyalBrickApp());

class RoyalBrickApp extends StatelessWidget {
  const RoyalBrickApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Royal Brick — Аудитор встреч',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Arial',
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF933D32)),
      scaffoldBackgroundColor: const Color(0xFFF7F5F2),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0DBD4)),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          side: const BorderSide(color: Color(0xFFD9D1C8)),
        ),
      ),
    ),
    home: const AuditPage(),
  );
}
