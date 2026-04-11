import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'screens/registro_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: "/", 
      routes: {
        "/": (context) => SplashScreen(),
        "/login": (context) => LoginScreen(),
        "/registro": (context) => RegistroScreen(),
        "/recuperar-contraseña": (context) => ForgotPasswordScreen(),
        // ✅ Elimina estas rutas fijas porque ahora usamos navegación con parámetros
        // "/home": (context) => HomeScreen(token: ''), 
        // "/settings": (context) => SettingsScreen(token: '')
      },
      // ✅ Usar onGenerateRoute para manejar rutas con parámetros
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
          case '/home':
            final token = settings.arguments as String? ?? '';
            return MaterialPageRoute(builder: (_) => HomeScreen(token: token));
          case '/settings':
            final token = settings.arguments as String? ?? '';
            return MaterialPageRoute(builder: (_) => SettingsScreen(token: token));
          default:
            return MaterialPageRoute(builder: (_) => SplashScreen());
        }
      },
    );
  }
}