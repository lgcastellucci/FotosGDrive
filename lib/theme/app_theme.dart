import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta baseada no mockup fornecido — claro, azul, amigável para o
/// usuário final (substitui o visual anterior de "log de terminal").
class AppColors {
  static const blue900 = Color(0xFF0D2B6B);
  static const blue700 = Color(0xFF1565C0);
  static const blue500 = Color(0xFF2196F3);
  static const blue200 = Color(0xFFBBDEFB);
  static const blue50 = Color(0xFFE3F2FD);

  static const green = Color(0xFF2E7D32);
  static const greenBg = Color(0xFFE8F5E9);

  static const amber = Color(0xFFF57F17);
  static const amberBg = Color(0xFFFFF8E1);

  static const red = Color(0xFFC62828);

  static const gray900 = Color(0xFF1A1A2E);
  static const gray700 = Color(0xFF37474F);
  static const gray400 = Color(0xFF90A4AE);
  static const gray100 = Color(0xFFECEFF1);

  static const surface = Color(0xFFFFFFFF);
  static const bg = Color(0xFFF0F4F8);
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = GoogleFonts.dmSansTextTheme(base.textTheme);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      textTheme: textTheme,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.blue700,
        secondary: AppColors.blue500,
        error: AppColors.red,
        surface: AppColors.surface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.blue700,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.dmSans(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  /// Fonte usada para timestamps/valores técnicos (equivalente ao
  /// 'DM Mono' do mockup — usamos DM Sans com letterSpacing/monoespaço
  /// aproximado via GoogleFonts, já que o pacote DM Mono completo não é
  /// necessário só para poucos rótulos).
  static TextStyle mono({double size = 11, Color? color, FontWeight? weight}) {
    return GoogleFonts.dmMono(
      fontSize: size,
      color: color ?? AppColors.gray400,
      fontWeight: weight ?? FontWeight.w500,
      letterSpacing: .02,
    );
  }
}
