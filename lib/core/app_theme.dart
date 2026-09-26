import 'package:flutter/material.dart';

class AppTheme {
  // Core colors
  static const seed = Color(0xFFEF5B72);
  static const bg = Color(0xFF0F172A);
  static const card = Color(0xFF1E293B);
  static const cardLight = Color(0xFF26354D);
  static const cardBorder = Color(0xFF334155);
  static const cardBorderGlow = Color(0xFF475569);

  // Vibrant Accents
  static const primaryPink = Color(0xFFEC4899);
  static const primaryPurple = Color(0xFF8B5CF6);
  static const cyanAccent = Color(0xFF06B6D4);
  static const emeraldOnline = Color(0xFF10B981);
  static const amberBusy = Color(0xFFF59E0B);
  static const goldStar = Color(0xFFFBBF24);

  // Curated Gradients
  static const primaryGradient = LinearGradient(
    colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const heroGradient = LinearGradient(
    colors: [Color(0xFF1E1B4B), Color(0xFF2E1065), Color(0xFF0F172A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const cardGradient = LinearGradient(
    colors: [Color(0xFF1E293B), Color(0xFF152033)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const cyanGradient = LinearGradient(
    colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const emeraldGradient = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF059669)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const amberGradient = LinearGradient(
    colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Warm Luxury Palette (Matching screenshots)
  static const bgCream = Color(0xFFFAF5EE);
  static const borderWarm = Color(0xFFF1E6D8);
  static const primaryOrange = Color(0xFFF95B3D);
  static const secondaryOrange = Color(0xFFFF7A45);
  static const softPeach = Color(0xFFFFECE5);
  static const textDark = Color(0xFF111827);
  static const textMuted = Color(0xFF6B7280);

  static const orangeGradient = LinearGradient(
    colors: [primaryOrange, secondaryOrange],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const peachGradient = LinearGradient(
    colors: [Color(0xFFFFF2EB), Color(0xFFFFE6D8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: primaryOrange,
      brightness: Brightness.light,
      surface: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: bgCream,
      appBarTheme: const AppBarTheme(
        backgroundColor: bgCream,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textDark),
        titleTextStyle: TextStyle(
          color: textDark,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: borderWarm, width: 1),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: softPeach,
        selectedColor: primaryOrange,
        side: const BorderSide(color: Color(0xFFFCDFD5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textDark),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderWarm),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderWarm),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryOrange, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryOrange,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryOrange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      surface: card,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: cardBorder, width: 1),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.05),
        selectedColor: primaryPink.withValues(alpha: 0.22),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF101827),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryPink, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
        ),
      ),
    );
  }
}
