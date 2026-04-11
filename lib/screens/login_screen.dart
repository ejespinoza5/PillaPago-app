// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'role_selection_screen.dart';
import 'resend_verification_screen.dart';
import 'home_screen.dart';
import 'verify_email_screen.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isGoogleLoading = false;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
    serverClientId:
        '332231473174-qjc4cdp9bo55o45eh0q9g4qvn1uen5ig.apps.googleusercontent.com',
  );

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  // ✅ Método auxiliar: usuario necesita onboarding si tiene rol 'pendiente'
  bool _necesitaOnboarding(Map<String, dynamic> usuario) {
    final String rol = usuario['rol'];
    return rol == 'pendiente';
  }

  // 🔹 Login con email y password
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

    // ✅ Verificar si hay mensaje de error
    if (response['message'] != null && response['success'] == false) {
      _showSnack(response['message'], isError: true);
      setState(() => _isLoading = false);
      return;
    }

    // ✅ Verificar si hay un reason específico
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

    // ✅ Verificar si el usuario existe en la respuesta
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

    // Guardar token
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("token", token);

    // ✅ Si el email NO está verificado, redirigir a verificación
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

    // ✅ Caso: usuario con rol 'pendiente' → elegir rol
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

    // ✅ Caso: usuario activo → ir al home
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

    // ✅ Manejar error 409 (correo ya registrado con email/contraseña)
    if (response['status'] == 409 || response['statusCode'] == 409) {
      await _googleSignIn.disconnect();
      _mostrarDialogoCuentaExistente(response['message']);
      setState(() => _isGoogleLoading = false);
      return;
    }

    // ✅ Verificar si la respuesta tiene token
    if (response['token'] == null) {
      _showSnack(response['message'] ?? 'Error al iniciar sesión con Google', isError: true);
      setState(() => _isGoogleLoading = false);
      return;
    }

    final usuario = response['usuario'];
    final String rol = usuario['rol'];
    final idNegocio = usuario['id_negocio'];
    final emailVerificado = usuario['email_verificado'] ?? false;

    // ✅ Si el email NO está verificado, redirigir a verificación
    if (!emailVerificado) {
      _showSnack('Debes verificar tu correo electrónico antes de continuar.', isError: false);
      
      // Guardar token temporalmente o pasar a la pantalla de verificación
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

    // ✅ Email verificado, continuar normalmente
    // Guardar token
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("token", response["token"]);

    _showSnack(response['message'] ?? 'Bienvenido con Google');

    // Si es pendiente y no tiene negocio → elegir rol
    if (rol == 'pendiente' && idNegocio == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RoleSelectionScreen(token: response['token']),
        ),
      );
    } else {
      // Ya tiene rol asignado → ir al home
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
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Text(
              'Cuenta existente',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mensaje ?? 'Este correo ya está registrado con email y contraseña.',
              style: TextStyle(fontSize: 14),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Puedes iniciar sesión con tu contraseña o restablecerla si no la recuerdas.',
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
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
            child: Text('Entendido', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Redirigir a recuperar contraseña
              Navigator.pushNamed(context, "/recuperar-contraseña");
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text('Restablecer contraseña'),
          ),
        ],
      );
    },
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              SizedBox(height: 30),
              Image.asset(
                "assets/images/logo+letra.png",
                height: 100,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.error,
                  size: 100,
                  color: Colors.blue,
                ),
              ),
              SizedBox(height: 20),
              Text(
                "Iniciar Sesión",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 30),
              TextField(
                controller: emailController,
                decoration: InputDecoration(
                  labelText: "Email",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              SizedBox(height: 15),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: "Password",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? CircularProgressIndicator(color: Colors.white)
                      : Text("Ingresar", style: TextStyle(fontSize: 16)),
                ),
              ),
              SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: _isGoogleLoading ? null : loginGoogle,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: Colors.grey[400]!),
                  ),
                  child: _isGoogleLoading
                      ? CircularProgressIndicator()
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.g_mobiledata, color: Colors.blue, size: 28),
                            SizedBox(width: 12),
                            Text("Continuar con Google", style: TextStyle(fontSize: 16)),
                          ],
                        ),
                ),
              ),
              SizedBox(height: 20),
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("¿No tienes cuenta? "),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushNamed(context, "/registro");
                        },
                        child: Text(
                          "Regístrate",
                          style: TextStyle(
                            color: Colors.blue, 
                            fontWeight: FontWeight.bold
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("¿Olvidaste tu contraseña? "),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushNamed(context, "/recuperar-contraseña");
                        },
                        child: Text(
                          "Recupérala aquí",
                          style: TextStyle(
                            color: Colors.blue, 
                            fontWeight: FontWeight.bold
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
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