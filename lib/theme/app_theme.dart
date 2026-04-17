 // lib/theme/app_theme.dart
import 'package:flutter/material.dart';

class AppTheme {
  // Colores principales
  static const Color green = Color(0xFF8DC63F);
  static const Color greenDark = Color(0xFF6EA52A);
  static const Color greenLight = Color(0xFFAEDD5C);
  static const Color greenDisabled = Color(0xFF4A6B1F);

  //Notificaciones
  static const Color info = Color(0xFF2196F3);
  
  // Fondos
  static const Color bgDark = Color(0xFF0E1510);
  static const Color bgMid = Color(0xFF141D12);
  static const Color bgSurf = Color(0xFF1A2416);
  static const Color surface = Color(0xFF1F2B1A);
  static const Color surfaceLight = Color(0xFF2A3824);
  
  // Bordes
  static const Color border = Color(0xFF2E3E27);
  static const Color borderLight = Color(0xFF3D5234);
  
  // Textos
  static const Color textPrimary = Color(0xFFF0F4EE);
  static const Color textSecondary = Color(0xFF8A9E82);
  static const Color textDisabled = Color(0xFF5A6B52);
  
  // Estados
  static const Color error = Color(0xFFE57373);
  static const Color errorBg = Color(0xFF442222);
  static const Color success = Color(0xFF81C784);
  static const Color successBg = Color(0xFF1E3A2E);
  static const Color warning = Color(0xFFFFB74D);
  static const Color warningBg = Color(0xFF3D2E1A);
  
  // Gradientes
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [greenDark, green, greenLight],
  );
  
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [bgDark, bgMid, bgSurf],
  );
  
  // ✅ Agregar buttonGradient (para botones)
  static BoxDecoration buttonGradient = BoxDecoration(
    gradient: primaryGradient,
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: green.withOpacity(0.4),
        blurRadius: 20,
        offset: const Offset(0, 6),
      ),
    ],
  );
  
  // Estilos de texto
  static const TextStyle headline1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: textPrimary,
    letterSpacing: 0.5,
  );
  
  static const TextStyle headline2 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: textPrimary,
  );
  
  static const TextStyle headline3 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: textPrimary,
  );
  
  static const TextStyle body1 = TextStyle(
    fontSize: 16,
    color: textPrimary,
  );
  
  static const TextStyle body2 = TextStyle(
    fontSize: 14,
    color: textSecondary,
  );
  
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    color: textSecondary,
  );
  
  static const TextStyle buttonText = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    letterSpacing: 0.5,
  );
}