// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'role_selection_screen.dart';
import 'resend_verification_screen.dart';
import 'home_screen.dart';
import 'verify_email_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isGoogleLoading = false;

  bool _obscurePassword = true;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
    serverClientId:
        '332231473174-qjc4cdp9bo55o45eh0q9g4qvn1uen5ig.apps.googleusercontent.com',
  );

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppTheme.error : AppTheme.green,
      ),
    );
  }

  bool _necesitaOnboarding(Map<String, dynamic> usuario) {
    final String rol = usuario['rol'];
    return rol == 'pendiente';
  }

  // 🔹 Login con email y password
  Future<void> login() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showSnack('Por favor completa todos los campos', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await ApiService.login({
        "email": email,
        "password": password,
      });

      print('Respuesta login: $response');

      if (response['message'] != null && response['success'] == false) {
        _showSnack(response['message'], isError: true);
        setState(() => _isLoading = false);
        return;
      }

      if (response['reason'] != null) {
        if (response['reason'] == 'email_not_verified') {
          _showSnack('Debes verificar tu correo', isError: true);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ResendVerificationScreen(email: email),
            ),
          );
          setState(() => _isLoading = false);
          return;
        }
      }

      final usuario = response['usuario'];
      if (usuario == null) {
        _showSnack(response['message'] ?? 'Error al iniciar sesión', isError: true);
        setState(() => _isLoading = false);
        return;
      }

      final necesitaOnboarding = _necesitaOnboarding(usuario);
      final token = response['token'];
      final emailVerificado = usuario['email_verificado'] ?? false;

      if (token == null) {
        _showSnack(response['message'] ?? 'Error al iniciar sesión', isError: true);
        setState(() => _isLoading = false);
        return;
      }

      print('Usuario rol: ${usuario['rol']}');
      print('ID Negocio: ${usuario['id_negocio']}');
      print('Email verificado: $emailVerificado');
      print('Necesita onboarding: $necesitaOnboarding');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("token", token);

      if (!emailVerificado) {
        _showSnack('Debes verificar tu correo electrónico antes de continuar.', isError: false);
        
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => VerifyEmailScreen(
                email: email,
                token: token,
              ),
            ),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      if (necesitaOnboarding) {
        _showSnack(response['message'] ?? 'Bienvenido');
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => RoleSelectionScreen(token: token),
          ),
          (route) => false,
        );
        setState(() => _isLoading = false);
        return;
      }

      _showSnack(response['message'] ?? 'Inicio de sesión exitoso');
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(token: token),
        ),
        (route) => false,
      );

    } catch (e) {
      print('Error en login: $e');
      _showSnack("Error al iniciar sesión: $e", isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 🔹 Login con Google
  Future<void> loginGoogle() async {
    setState(() => _isGoogleLoading = true);

    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();

      if (account == null) {
        setState(() => _isGoogleLoading = false);
        return;
      }

      final GoogleSignInAuthentication auth = await account.authentication;

      if (auth.idToken == null) {
        _showSnack('No se pudo obtener el idToken de Google', isError: true);
        setState(() => _isGoogleLoading = false);
        return;
      }

      final response = await ApiService.loginGoogle(auth.idToken!);

      print('Respuesta Google login: $response');

      if (response['status'] == 409 || response['statusCode'] == 409) {
        await _googleSignIn.disconnect();
        _mostrarDialogoCuentaExistente(response['message']);
        setState(() => _isGoogleLoading = false);
        return;
      }

      if (response['token'] == null) {
        _showSnack(response['message'] ?? 'Error al iniciar sesión con Google', isError: true);
        setState(() => _isGoogleLoading = false);
        return;
      }

      final usuario = response['usuario'];
      final String rol = usuario['rol'];
      final idNegocio = usuario['id_negocio'];
      final emailVerificado = usuario['email_verificado'] ?? false;

      if (!emailVerificado) {
        _showSnack('Debes verificar tu correo electrónico antes de continuar.', isError: false);
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("token", response["token"]);
        
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => VerifyEmailScreen(
                email: usuario['email'],
              ),
            ),
          );
        }
        setState(() => _isGoogleLoading = false);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("token", response["token"]);

      _showSnack(response['message'] ?? 'Bienvenido con Google');

      if (rol == 'pendiente' && idNegocio == null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => RoleSelectionScreen(token: response['token']),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomeScreen(token: response['token']),
          ),
        );
      }

    } catch (e) {
      print('Error en loginGoogle: $e');
      _showSnack('Error al iniciar sesión con Google.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
      }
    }
  }

  void _mostrarDialogoCuentaExistente(String? mensaje) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 28),
              const SizedBox(width: 12),
              Text(
                'Cuenta existente',
                style: AppTheme.headline3,
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mensaje ?? 'Este correo ya está registrado con email y contraseña.',
                style: AppTheme.body2,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: AppTheme.green, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Puedes iniciar sesión con tu contraseña o restablecerla si no la recuerdas.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text('Entendido', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, "/recuperar-contraseña");
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Restablecer contraseña'),
            ),
          ],
        );
      },
    );
  }

@override
Widget build(BuildContext context) {
  return Scaffold(
    body: Container(
      decoration: BoxDecoration(
        gradient: AppTheme.backgroundGradient,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          // ✅ Hacer que el contenido ocupe al menos toda la altura
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - 
                         MediaQuery.of(context).padding.top - 
                         MediaQuery.of(context).padding.bottom - 40,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 30),
                Image.asset(
                  "assets/images/logo+letra.png",
                  height: 100,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.error,
                    size: 100,
                    color: AppTheme.green,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "Iniciar Sesión",
                  style: AppTheme.headline2,
                ),
                const SizedBox(height: 30),
                
                // Campo email
                TextField(
                  controller: emailController,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: "Email",
                    prefixIcon: Icon(Icons.email_outlined, color: AppTheme.green),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 15),
                
                // Campo password con ojo
TextField(
  controller: passwordController,
  obscureText: _obscurePassword,
  style: const TextStyle(color: AppTheme.textPrimary),
  decoration: InputDecoration(
    labelText: "Contraseña",
    prefixIcon: Icon(Icons.lock_outline, color: AppTheme.green),
    suffixIcon: IconButton(
      icon: Icon(
        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        color: AppTheme.textSecondary,
        size: 20,
      ),
      onPressed: () {
        setState(() {
          _obscurePassword = !_obscurePassword;
        });
      },
    ),
  ),
),
                const SizedBox(height: 20),
                
                // Botón Ingresar
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: DecoratedBox(
                    decoration: AppTheme.buttonGradient,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text(
                              'Ingresar',
                              style: AppTheme.buttonText,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Separador
                Row(
                  children: [
                    Expanded(child: Divider(color: AppTheme.border, thickness: 1)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'o continúa con',
                        style: AppTheme.caption,
                      ),
                    ),
                    Expanded(child: Divider(color: AppTheme.border, thickness: 1)),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Botón Google
SizedBox(
  width: double.infinity,
  height: 52,
  child: OutlinedButton(
    onPressed: _isGoogleLoading ? null : loginGoogle,
    style: OutlinedButton.styleFrom(
      side: BorderSide(color: AppTheme.border, width: 1.2),
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    child: _isGoogleLoading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: AppTheme.green,
              strokeWidth: 2.5,
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ✅ Imagen del logo de Google
              Image.asset(
                'assets/images/google_logo.png',
                width: 24,
                height: 24,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.g_mobiledata, color: AppTheme.green, size: 24),
              ),
              const SizedBox(width: 12),
              const Text(
                "Continuar con Google",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
  ),
),
                const SizedBox(height: 24),
                
                // Links
                Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("¿No tienes cuenta? ", style: AppTheme.body2),
                        GestureDetector(
                          onTap: () {
                            Navigator.pushNamed(context, "/registro");
                          },
                          child: Text(
                            "Regístrate",
                            style: TextStyle(
                              color: AppTheme.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("¿Olvidaste tu contraseña? ", style: AppTheme.body2),
                        GestureDetector(
                          onTap: () {
                            Navigator.pushNamed(context, "/recuperar-contraseña");
                          },
                          child: Text(
                            "Recupérala aquí",
                            style: TextStyle(
                              color: AppTheme.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                
                // ✅ Espacio adicional para evitar que quede pegado al fondo
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}