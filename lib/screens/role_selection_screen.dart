// lib/screens/role_selection_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';

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

  String? _rolSeleccionado; // 'dueno' o 'empleado'
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
          title: Text('Cerrar Sesión'),
          content: Text('¿Estás seguro de que deseas cerrar sesión?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('Cerrar Sesión'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      // Limpiar tokens
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

  Future<void> _confirmar() async {
    print('=== INICIO _confirmar ===');
    
    // Validaciones
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

      // Verificar la estructura correcta de la respuesta
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
          ),
        );
        
        // Navegar al HomeScreen
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => HomeScreen(token: token),
          ),
          (route) => false,
        );
      } else {
        // Si hay un mensaje de error específico, mostrarlo
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
      appBar: AppBar(
        title: const Text('¿Cuál es tu rol?'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          // Botón de cerrar sesión
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: _cerrarSesion,
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selecciona cómo usarás la app',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            // Tarjetas de selección
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

            // Campo dinámico según rol
            if (_rolSeleccionado == 'dueno') ...[
              const Text('Nombre del negocio',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _negocioController,
                decoration: InputDecoration(
                  hintText: 'Ej: Ferretería Espinoza',
                  prefixIcon: const Icon(Icons.business),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],

            if (_rolSeleccionado == 'empleado') ...[
              const Text('Código de invitación',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _codigoController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'Ej: KGSQ3AT7',
                  prefixIcon: const Icon(Icons.key_rounded),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],

            const SizedBox(height: 16),
            if (_errorMessage.isNotEmpty)
              Text(_errorMessage, style: const TextStyle(color: Colors.red)),

            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _confirmar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Continuar', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Widget de tarjeta reutilizable
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
              ? Colors.blue.withOpacity(0.1)
              : Colors.grey.withOpacity(0.05),
          border: Border.all(
            color: seleccionado ? Colors.blue : Colors.grey.shade300,
            width: seleccionado ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icono,
                size: 36, color: seleccionado ? Colors.blue : Colors.grey),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: seleccionado ? Colors.blue : Colors.black87,
                    )),
                Text(descripcion,
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 13)),
              ],
            ),
            const Spacer(),
            if (seleccionado)
              const Icon(Icons.check_circle, color: Colors.blue),
          ],
        ),
      ),
    );
  }
}