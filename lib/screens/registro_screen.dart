import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'verify_email_screen.dart';
import 'role_selection_screen.dart';
import 'home_screen.dart'; 
// ─── Paleta PillaPago (extraída del logo) ───────────────────────────────────
const _kGreen        = Color(0xFF8DC63F); // verde lima del logo
const _kGreenDark    = Color(0xFF6EA52A); // verde oscuro para sombras
const _kGreenLight   = Color(0xFFAEDD5C); // verde claro para acentos hover
const _kBg           = Color(0xFF0E1510); // fondo casi negro con matiz verde
const _kBgMid        = Color(0xFF141D12); // gradiente mid
const _kBgSurf       = Color(0xFF1A2416); // gradiente bottom
const _kSurface      = Color(0xFF1F2B1A); // tarjetas / campos
const _kBorder       = Color(0xFF2E3E27); // bordes sutiles
const _kTextPrimary  = Color(0xFFF0F4EE); // blanco cálido
const _kTextSecond   = Color(0xFF8A9E82); // gris verdoso
// ─────────────────────────────────────────────────────────────────────────────

class RegistroScreen extends StatefulWidget {
  @override
  _RegistroScreenState createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen>
    with SingleTickerProviderStateMixin {
  final nombreController          = TextEditingController();
  final emailController           = TextEditingController();
  final passwordController        = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
  scopes: ['email'],
  serverClientId: '332231473174-qjc4cdp9bo55o45eh0q9g4qvn1uen5ig.apps.googleusercontent.com',
);

  File? imagen;
  final picker = ImagePicker();
  bool _obscurePassword = true;
  bool _obscureConfirm  = true;
  bool _isLoading = false;
  String? _passwordError;

  late AnimationController _animController;
  late Animation<double>   _fadeIn;
  late Animation<Offset>   _slideIn;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeIn  = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
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

  // ── Imagen ────────────────────────────────────────────────────────────────
  void _mostrarOpcionesImagen() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _kSurface,
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
                color: _kBorder,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Foto de perfil',
              style: TextStyle(
                color: _kTextPrimary,
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

  // ── Registro ──────────────────────────────────────────────────────────────
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
        'nombre':   nombreController.text,
        'email':    emailController.text,
        'password': passwordController.text,
      },
      imagen,
    );

    print('Respuesta completa del registro: $response');

    // ✅ Verificar si el email no está verificado (campo email_verificado = false)
    if (response['usuario'] != null && response['usuario']['email_verificado'] == false) {
      _showSnack('Te hemos enviado un código de verificación a tu correo electrónico.');
      
      // Redirigir a pantalla de verificación
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
    
    // ✅ Verificar si hay token (registro exitoso sin verificación)
    if (response['token'] != null && response['token'].toString().isNotEmpty) {
      // Guardar token
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("token", response['token']);
      
      _showSnack('Registro exitoso. Completa tu perfil.');
      
      // Redirigir a selección de rol
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
    
    // ✅ Si el backend envía verification_required
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
    
    // ✅ Error
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
        backgroundColor: isError ? const Color(0xFFB71C1C) : _kGreenDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────
  bool _isGoogleLoading = false;



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
      // Desconectar la cuenta de Google para este intento fallido
      await _googleSignIn.disconnect();
      
      // Mostrar diálogo informativo
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

    // Guardar token
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("token", response["token"]);

    final usuario = response['usuario'];
    final String rol = usuario['rol'];
    final idNegocio = usuario['id_negocio'];

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
  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Fix: barra de estado del celular visible (iconos blancos)
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_kBg, _kBgMid, _kBgSurf],
          ),
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
                    // ── Logo ───────────────────────────────────────────────
                    Image.asset('assets/images/logo+letra.png', height: 72),
                    const SizedBox(height: 28),

                    // ── Títulos ────────────────────────────────────────────
                    const Text(
                      'Crear cuenta',
                      style: TextStyle(
                        color: _kTextPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Únete a PillaPago hoy',
                      style: TextStyle(color: _kTextSecond, fontSize: 14),
                    ),

                    const SizedBox(height: 30),

                    // ── Avatar ────────────────────────────────────────────
                    GestureDetector(
                      onTap: _mostrarOpcionesImagen,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          // Anillo exterior decorativo
                          Container(
                            width: 118, height: 118,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _kGreen.withOpacity(0.25), width: 2.5),
                            ),
                          ),
                          // Círculo principal
                          Padding(
                            padding: const EdgeInsets.all(5),
                            child: Container(
                              width: 108, height: 108,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [_kGreenDark, _kGreen],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _kGreen.withOpacity(0.35),
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
                          // Badge cámara
                          Positioned(
                            right: 2, bottom: 2,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: _kGreen,
                                shape: BoxShape.circle,
                                border: Border.all(color: _kBg, width: 2.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: _kGreen.withOpacity(0.45),
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
                        icon: const Icon(Icons.close_rounded,
                            size: 15, color: Colors.redAccent),
                        label: const Text(
                          'Quitar foto',
                          style: TextStyle(
                              color: Colors.redAccent, fontSize: 13),
                        ),
                      ),
                    ],

                    const SizedBox(height: 30),

                    // ── Campos ────────────────────────────────────────────
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
                          color: _kTextSecond, size: 20,
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
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
                          color: _kTextSecond, size: 20,
                        ),
                        onPressed: () => setState(
                            () => _obscureConfirm = !_obscureConfirm),
                      ),
                      onChanged: (_) {
                        if (_passwordError != null) {
                          setState(() => _passwordError = null);
                        }
                      },
                    ),

                    // Mensaje de error contraseña
                    if (_passwordError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, left: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Colors.redAccent, size: 15),
                            const SizedBox(width: 6),
                            Text(
                              _passwordError!,
                              style: const TextStyle(
                                  color: Colors.redAccent, fontSize: 12),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 28),

                    // ── Botón Registrarse ─────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_kGreenDark, _kGreen, _kGreenLight],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: _kGreen.withOpacity(0.40),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : registrar,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5),
                                )
                              : const Text(
                                  'Crear cuenta',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Separador OR ──────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: _kBorder,
                            thickness: 1,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'o continúa con',
                            style: TextStyle(
                              color: _kTextSecond,
                              fontSize: 12,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: _kBorder,
                            thickness: 1,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ── Botón Google ──────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: _isGoogleLoading ? null : loginGoogle,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: _kBorder, width: 1.2),
                          backgroundColor: _kSurface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isGoogleLoading
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(
                                  color: _kGreen, strokeWidth: 2.5),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Logo G de Google incrustado
                                  Container(
                                    width: 22, height: 22,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                    ),
                                    child: CustomPaint(
                                      painter: _GoogleLogoPainter(),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'Continuar con Google',
                                    style: TextStyle(
                                      color: _kTextPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Link login ────────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          '¿Ya tienes cuenta? ',
                          style: TextStyle(color: _kTextSecond, fontSize: 14),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Text(
                            'Inicia sesión',
                            style: TextStyle(
                              color: _kGreen,
                              fontSize: 14,
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

  // ── Campo reutilizable ────────────────────────────────────────────────────
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
    final borderColor = hasError
        ? Colors.redAccent.withOpacity(0.7)
        : _kBorder;
    final iconColor = hasError ? Colors.redAccent : _kGreen;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: hasError ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: hasError
                ? Colors.redAccent.withOpacity(0.15)
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
        style: const TextStyle(color: _kTextPrimary, fontSize: 15),
        cursorColor: _kGreen,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: hasError ? Colors.redAccent : _kTextSecond, fontSize: 14),
          prefixIcon: Icon(icon, color: iconColor, size: 20),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          floatingLabelStyle: TextStyle(
            color: hasError ? Colors.redAccent : _kGreen,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ─── Bottom-sheet option ─────────────────────────────────────────────────────
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
              color: _kGreen.withOpacity(0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _kGreen.withOpacity(0.35)),
            ),
            child: Icon(icon, color: _kGreen, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(color: _kTextSecond, fontSize: 13)),
        ],
      ),
    );
  }
}

// ─── Google "G" logo painter ──────────────────────────────────────────────────
class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Fondo blanco circular
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = Colors.white,
    );

    // Colores oficiales de Google
    const red    = Color(0xFFEA4335);
    const blue   = Color(0xFF4285F4);
    const yellow = Color(0xFFFBBC05);
    const green  = Color(0xFF34A853);

    final sw = size.width;
    final sh = size.height;
    final cx = sw / 2;
    final cy = sh / 2;

    // Arco azul (parte derecha)
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw * 0.18
      ..strokeCap = StrokeCap.butt;

    final rect = Rect.fromCircle(center: center, radius: radius * 0.62);

    arcPaint.color = blue;
    canvas.drawArc(rect, -0.52, 1.57, false, arcPaint); // top → right

    arcPaint.color = yellow;
    canvas.drawArc(rect, 1.05, 0.79, false, arcPaint); // right → bottom

    arcPaint.color = green;
    canvas.drawArc(rect, 1.84, 1.05, false, arcPaint); // bottom → left

    arcPaint.color = red;
    canvas.drawArc(rect, 2.89, 1.78, false, arcPaint); // left → top

    // Barra horizontal azul (parte de la "G")
    final barPaint = Paint()
      ..color = blue
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 0.01, cy - sw * 0.09, radius * 0.62, sw * 0.18),
        Radius.circular(sw * 0.04),
      ),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}