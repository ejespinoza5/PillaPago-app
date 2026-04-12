// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/registro_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/role_selection_screen.dart';
import 'screens/pending_transfers_screen.dart';
import 'screens/edit_transferencia_screen.dart';
import 'screens/edit_profile_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/change_email_screen.dart';
import 'screens/qr_scanner_screen.dart';

void main() {
  // ✅ Configurar la barra de navegación y la barra de estado
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.bgDark, // ✅ Color de la barra de navegación
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: Colors.transparent,
  ));
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PillaPago',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppTheme.bgDark,
        primaryColor: AppTheme.green,
        colorScheme: const ColorScheme.dark(
          primary: AppTheme.green,
          secondary: AppTheme.greenLight,
          surface: AppTheme.surface,
          error: AppTheme.error,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: AppTheme.textPrimary,
            shadowColor: Colors.transparent,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: AppTheme.buttonText,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppTheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppTheme.green, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppTheme.error),
          ),
          labelStyle: const TextStyle(color: AppTheme.textSecondary),
          hintStyle: const TextStyle(color: AppTheme.textSecondary),
          prefixIconColor: AppTheme.green,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        ),
        textTheme: const TextTheme(
          displayLarge: AppTheme.headline1,
          displayMedium: AppTheme.headline2,
          displaySmall: AppTheme.headline3,
          bodyLarge: AppTheme.body1,
          bodyMedium: AppTheme.body2,
          bodySmall: AppTheme.caption,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: AppTheme.textPrimary),
          titleTextStyle: AppTheme.headline3,
        ),
        cardTheme: CardThemeData(
          color: AppTheme.surface,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          titleTextStyle: AppTheme.headline3.copyWith(color: AppTheme.textPrimary),
          contentTextStyle: AppTheme.body2,
        ),
      ),
      initialRoute: "/",
      routes: {
        "/": (context) => SplashScreen(),
        "/login": (context) => LoginScreen(),
        "/registro": (context) => RegistroScreen(),
        "/recuperar-contraseña": (context) => ForgotPasswordScreen(),
      },
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(builder: (_) => SplashScreen());
          case '/login':
            return MaterialPageRoute(builder: (_) => LoginScreen());
          case '/registro':
            return MaterialPageRoute(builder: (_) => RegistroScreen());
          case '/recuperar-contraseña':
            return MaterialPageRoute(builder: (_) => ForgotPasswordScreen());
          case '/role-selection':
            final token = settings.arguments as String? ?? '';
            return MaterialPageRoute(builder: (_) => RoleSelectionScreen(token: token));
          case '/home':
            final token = settings.arguments as String? ?? '';
            return MaterialPageRoute(builder: (_) => HomeScreen(token: token));
          case '/settings':
            final token = settings.arguments as String? ?? '';
            return MaterialPageRoute(builder: (_) => SettingsScreen(token: token));
          case '/pending-transfers':
            final token = settings.arguments as String? ?? '';
            return MaterialPageRoute(builder: (_) => PendingTransfersScreen(token: token));
          case '/edit-transferencia':
            final args = settings.arguments as Map<String, dynamic>?;
            return MaterialPageRoute(
              builder: (_) => EditTransferenciaScreen(
                token: args?['token'] ?? '',
                transferencia: args?['transferencia'] ?? {},
                puedeEditar: args?['puedeEditar'] ?? false,
              ),
            );
          case '/edit-profile':
            final args = settings.arguments as Map<String, dynamic>?;
            return MaterialPageRoute(
              builder: (_) => EditProfileScreen(
                token: args?['token'] ?? '',
                userData: args?['userData'] ?? {},
              ),
            );
          case '/change-password':
            final token = settings.arguments as String? ?? '';
            return MaterialPageRoute(builder: (_) => ChangePasswordScreen(token: token));
          case '/change-email':
            final args = settings.arguments as Map<String, dynamic>?;
            return MaterialPageRoute(
              builder: (_) => ChangeEmailScreen(
                token: args?['token'] ?? '',
                currentEmail: args?['currentEmail'] ?? '',
              ),
            );
          case '/qr-scanner':
            return MaterialPageRoute(builder: (_) => const QrScannerScreen());
          default:
            return MaterialPageRoute(builder: (_) => SplashScreen());
        }
      },
    );
  }
}