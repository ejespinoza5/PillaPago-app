// lib/screens/registro_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'verify_email_screen.dart';
import 'role_selection_screen.dart';
import 'home_screen.dart';

class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key});

  @override
  _RegistroScreenState createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen>
    with SingleTickerProviderStateMixin {
  final nombreController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
    serverClientId: '332231473174-qjc4cdp9bo55o45eh0q9g4qvn1uen5ig.apps.googleusercontent.com',
  );

  File? imagen;
  final picker = ImagePicker();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _passwordError;

  late AnimationController _animController;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideIn;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideIn = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    nombreController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  void _mostrarOpcionesImagen() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Foto de perfil',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _SheetOption(
                  icon: Icons.photo_library_rounded,
                  label: 'Galería',
                  onTap: () async {
                    Navigator.pop(context);
                    final f = await picker.pickImage(
                        source: ImageSource.gallery, imageQuality: 75);
                    if (f != null) setState(() => imagen = File(f.path));
                  },
                ),
                _SheetOption(
                  icon: Icons.camera_alt_rounded,
                  label: 'Cámara',
                  onTap: () async {
                    Navigator.pop(context);
                    final f = await picker.pickImage(
                        source: ImageSource.camera, imageQuality: 75);
                    if (f != null) setState(() => imagen = File(f.path));
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void registrar() async {
    if (nombreController.text.isEmpty ||
        emailController.text.isEmpty ||
        passwordController.text.isEmpty ||
        confirmPasswordController.text.isEmpty) {
      _showSnack('Por favor completa todos los campos.', isError: true);
      return;
    }
    if (passwordController.text != confirmPasswordController.text) {
      setState(() => _passwordError = 'Las contraseñas no coinciden');
      _showSnack('Las contraseñas no coinciden.', isError: true);
      return;
    }
    setState(() => _passwordError = null);
    setState(() => _isLoading = true);
    
    try {
      final response = await ApiService.registerWithImage(
        {
          'nombre': nombreController.text,
          'email': emailController.text,
          'password': passwordController.text,
        },
        imagen,
      );

      print('Respuesta completa del registro: $response');

      if (response['usuario'] != null && response['usuario']['email_verificado'] == false) {
        _showSnack('Te hemos enviado un código de verificación a tu correo electrónico.');
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => VerifyEmailScreen(
                email: emailController.text,
                token: response['token'],
              ),
            ),
          );
        }
        return;
      }
      
      if (response['token'] != null && response['token'].toString().isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("token", response['token']);
        _showSnack('Registro exitoso. Completa tu perfil.');
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => RoleSelectionScreen(token: response['token']),
            ),
          );
        }
        return;
      }
      
      if (response['verification_required'] == true) {
        _showSnack(response['message'] ?? 'Código de verificación enviado a tu correo');
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => VerifyEmailScreen(
                email: emailController.text,
                token: response['token'],
              ),
            ),
          );
        }
        return;
      }
      
      _showSnack(response['message'] ?? 'Error al registrar', isError: true);
      
    } catch (e) {
      print('Error en registro: $e');
      _showSnack('Ocurrió un error al registrar: ${e.toString()}', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: Colors.white, size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(msg)),
        ]),
        backgroundColor: isError ? AppTheme.error : AppTheme.greenDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

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

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("token", response["token"]);

      final usuario = response['usuario'];
      final String rol = usuario['rol'];
      final idNegocio = usuario['id_negocio'];

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
      print(e);
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
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));
    
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeIn,
            child: SlideTransition(
              position: _slideIn,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset('assets/images/logo+letra.png', height: 72),
                    const SizedBox(height: 28),

                    const Text(
                      'Crear cuenta',
                      style: AppTheme.headline1,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Únete a PillaPago hoy',
                      style: AppTheme.body2,
                    ),

                    const SizedBox(height: 30),

                    // Avatar
                    GestureDetector(
                      onTap: _mostrarOpcionesImagen,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            width: 118, height: 118,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.green.withOpacity(0.25), width: 2.5),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(5),
                            child: Container(
                              width: 108, height: 108,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: AppTheme.primaryGradient,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.green.withOpacity(0.35),
                                    blurRadius: 22,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: imagen != null
                                  ? ClipOval(
                                      child: Image.file(
                                        imagen!,
                                        width: 108, height: 108,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.person_rounded,
                                      size: 46,
                                      color: Colors.white70,
                                    ),
                            ),
                          ),
                          Positioned(
                            right: 2, bottom: 2,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppTheme.green,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppTheme.bgDark, width: 2.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.green.withOpacity(0.45),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                size: 15, color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (imagen != null) ...[
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: () => setState(() => imagen = null),
                        icon: const Icon(Icons.close_rounded, size: 15, color: AppTheme.error),
                        label: const Text(
                          'Quitar foto',
                          style: TextStyle(color: AppTheme.error, fontSize: 13),
                        ),
                      ),
                    ],

                    const SizedBox(height: 30),

                    _buildField(
                      controller: nombreController,
                      label: 'Nombre completo',
                      icon: Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: emailController,
                      label: 'Correo electrónico',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: passwordController,
                      label: 'Contraseña',
                      icon: Icons.lock_outline_rounded,
                      obscure: _obscurePassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: AppTheme.textSecondary, size: 20,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),

                    const SizedBox(height: 14),
                    _buildField(
                      controller: confirmPasswordController,
                      label: 'Confirmar contraseña',
                      icon: Icons.lock_reset_rounded,
                      obscure: _obscureConfirm,
                      hasError: _passwordError != null,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: AppTheme.textSecondary, size: 20,
                        ),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                      onChanged: (_) {
                        if (_passwordError != null) {
                          setState(() => _passwordError = null);
                        }
                      },
                    ),

                    if (_passwordError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, left: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: AppTheme.error, size: 15),
                            const SizedBox(width: 6),
                            Text(
                              _passwordError!,
                              style: const TextStyle(color: AppTheme.error, fontSize: 12),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 28),

                    // Botón Registrarse
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: DecoratedBox(
                        decoration: AppTheme.buttonGradient,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : registrar,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5),
                                )
                              : const Text(
                                  'Crear cuenta',
                                  style: AppTheme.buttonText,
                                ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

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

                    // Botón Google con mejor icono
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
                                width: 20, height: 20,
                                child: CircularProgressIndicator(
                                  color: AppTheme.green, strokeWidth: 2.5),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Icono de Google más limpio
                                  Image.asset(
                                    'assets/images/google_logo.png',
                                    width: 24,
                                    height: 24,
                                    errorBuilder: (context, error, stackTrace) => 
                                      const Icon(Icons.g_mobiledata, color: AppTheme.green, size: 24),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'Continuar con Google',
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Link login
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          '¿Ya tienes cuenta? ',
                          style: AppTheme.body2,
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Text(
                            'Inicia sesión',
                            style: TextStyle(
                              color: AppTheme.green,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    bool hasError = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
  }) {
    final borderColor = hasError ? AppTheme.error : AppTheme.border;
    final iconColor = hasError ? AppTheme.error : AppTheme.green;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: hasError ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: hasError
                ? AppTheme.error.withOpacity(0.15)
                : Colors.black.withOpacity(0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
        cursorColor: AppTheme.green,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: hasError ? AppTheme.error : AppTheme.textSecondary, fontSize: 14),
          prefixIcon: Icon(icon, color: iconColor, size: 20),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          floatingLabelStyle: TextStyle(
            color: hasError ? AppTheme.error : AppTheme.green,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: AppTheme.green.withOpacity(0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.green.withOpacity(0.35)),
            ),
            child: Icon(icon, color: AppTheme.green, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}