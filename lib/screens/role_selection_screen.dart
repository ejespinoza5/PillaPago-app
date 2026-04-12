// lib/screens/role_selection_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'qr_scanner_screen.dart';

class RoleSelectionScreen extends StatefulWidget {
  final String token;

  const RoleSelectionScreen({super.key, required this.token});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _negocioController = TextEditingController();
  final TextEditingController _codigoController = TextEditingController();

  String? _rolSeleccionado;
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void dispose() {
    _negocioController.dispose();
    _codigoController.dispose();
    super.dispose();
  }

  Future<String> _getValidToken() async {
    if (widget.token.isNotEmpty) {
      return widget.token;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token') ?? '';
  }

  Future<void> _cerrarSesion() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Cerrar Sesión', style: TextStyle(color: AppTheme.textPrimary)),
          content: const Text('¿Estás seguro de que deseas cerrar sesión?', style: TextStyle(color: AppTheme.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppTheme.error),
              child: Text('Cerrar Sesión', style: TextStyle(color: AppTheme.error)),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await ApiService.clearTokens();
      
      final GoogleSignIn googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
      
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _escanearQR() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const QrScannerScreen(),
      ),
    );
    
    if (result != null && result is String && result.isNotEmpty) {
      setState(() {
        _codigoController.text = result;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✅ Código escaneado correctamente'),
          backgroundColor: AppTheme.green,
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _confirmar() async {
    print('=== INICIO _confirmar ===');
    
    if (_rolSeleccionado == null) {
      print('Error: Rol no seleccionado');
      setState(() => _errorMessage = 'Selecciona un rol para continuar');
      return;
    }

    if (_rolSeleccionado == 'dueno' && _negocioController.text.trim().isEmpty) {
      print('Error: Nombre de negocio vacío');
      setState(() => _errorMessage = 'Ingresa el nombre del negocio');
      return;
    }

    if (_rolSeleccionado == 'empleado' && _codigoController.text.trim().isEmpty) {
      print('Error: Código de invitación vacío');
      setState(() => _errorMessage = 'Ingresa el código de invitación');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final token = await _getValidToken();
      if (token.isEmpty) {
        setState(() {
          _errorMessage = 'Sesión expirada. Por favor inicia sesión nuevamente.';
          _isLoading = false;
        });
        return;
      }

      print('Llamando a API con rol: $_rolSeleccionado');
      Map<String, dynamic> result;

      if (_rolSeleccionado == 'dueno') {
        print('Registrando negocio: ${_negocioController.text.trim()}');
        result = await _apiService.registerNegocio(
          _negocioController.text.trim(),
          token,
        );
      } else {
        print('Uniendo a negocio con código: ${_codigoController.text.trim()}');
        result = await _apiService.joinNegocio(
          _codigoController.text.trim(),
          token,
        );
      }

      print('Respuesta de API: $result');

      if (!mounted) {
        print('Widget no mounted, cancelando');
        return;
      }

      setState(() => _isLoading = false);

      final data = result['data'];
      final negocio = data?['negocio'];
      final usuario = data?['usuario'];
      
      if (result['success'] == true || (negocio != null && usuario != null)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _rolSeleccionado == 'dueno'
                  ? '¡Negocio "${negocio?['nombre_negocio']}" creado!'
                  : '¡Te uniste a "${negocio?['nombre_negocio']}"!',
            ),
            backgroundColor: AppTheme.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
        
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => HomeScreen(token: token),
          ),
          (route) => false,
        );
      } else {
        setState(() => _errorMessage = result['message'] ?? 'Ocurrió un error al procesar la solicitud');
      }
    } catch (e) {
      print('Excepción capturada: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error de conexión: ${e.toString()}';
        });
      }
    }
  }

@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: AppTheme.bgDark,
    appBar: AppBar(
      title: const Text('¿Cuál es tu rol?', style: TextStyle(color: AppTheme.textPrimary)),
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      actions: [
        IconButton(
          icon: Icon(Icons.logout, color: AppTheme.textPrimary),
          onPressed: _cerrarSesion,
          tooltip: 'Cerrar sesión',
        ),
      ],
    ),
    body: Container(
      decoration: const BoxDecoration(
        gradient: AppTheme.backgroundGradient,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Selecciona cómo usarás la app',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 24),

                    _RolCard(
                      titulo: 'Soy dueño',
                      descripcion: 'Crea y administra tu negocio',
                      icono: Icons.store_rounded,
                      seleccionado: _rolSeleccionado == 'dueno',
                      onTap: () => setState(() {
                        _rolSeleccionado = 'dueno';
                        _errorMessage = '';
                      }),
                    ),
                    const SizedBox(height: 12),
                    _RolCard(
                      titulo: 'Soy empleado',
                      descripcion: 'Únete al negocio con un código',
                      icono: Icons.badge_rounded,
                      seleccionado: _rolSeleccionado == 'empleado',
                      onTap: () => setState(() {
                        _rolSeleccionado = 'empleado';
                        _errorMessage = '';
                      }),
                    ),

                    const SizedBox(height: 24),

                    if (_rolSeleccionado == 'dueno') ...[
                      const Text('Nombre del negocio',
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _negocioController,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Ej: Ferretería Espinoza',
                          prefixIcon: Icon(Icons.business, color: AppTheme.green),
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
                        ),
                      ),
                    ],

                    if (_rolSeleccionado == 'empleado') ...[
                      const Text('Código de invitación',
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _codigoController,
                              textCapitalization: TextCapitalization.characters,
                              style: const TextStyle(color: AppTheme.textPrimary),
                              decoration: InputDecoration(
                                hintText: 'Ej: KGSQ3AT7',
                                prefixIcon: Icon(Icons.key_rounded, color: AppTheme.green),
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
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            decoration: BoxDecoration(
                              gradient: AppTheme.primaryGradient,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.green.withOpacity(0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _escanearQR,
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  child: Row(
                                    children: [
                                      Icon(Icons.qr_code_scanner, color: Colors.white, size: 24),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Escanear',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    // ✅ Espacio flexible que empuja el contenido hacia arriba
                    const SizedBox(height: 20),
                    
                    // Mensaje de error (si existe)
                    if (_errorMessage.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.errorBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.error),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, size: 20, color: AppTheme.error),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _errorMessage,
                                style: TextStyle(color: AppTheme.error),
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    // Botón Continuar
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _confirmar,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                              )
                            : const Text('Continuar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
}

class _RolCard extends StatelessWidget {
  final String titulo;
  final String descripcion;
  final IconData icono;
  final bool seleccionado;
  final VoidCallback onTap;

  const _RolCard({
    required this.titulo,
    required this.descripcion,
    required this.icono,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: seleccionado
              ? AppTheme.green.withOpacity(0.1)
              : AppTheme.surface,
          border: Border.all(
            color: seleccionado ? AppTheme.green : AppTheme.border,
            width: seleccionado ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icono,
                size: 36, color: seleccionado ? AppTheme.green : AppTheme.textSecondary),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: seleccionado ? AppTheme.green : AppTheme.textPrimary,
                    )),
                Text(descripcion,
                    style: TextStyle(
                      color: seleccionado ? AppTheme.textSecondary : AppTheme.textSecondary,
                      fontSize: 13,
                    )),
              ],
            ),
            const Spacer(),
            if (seleccionado)
              Icon(Icons.check_circle, color: AppTheme.green),
          ],
        ),
      ),
    );
  }
}