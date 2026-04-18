// lib/screens/edit_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import 'package:flutter/foundation.dart';

class EditProfileScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic> userData;

  const EditProfileScreen({
    Key? key,
    required this.token,
    required this.userData,
  }) : super(key: key);

  @override
  _EditProfileScreenState createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late ApiService _apiService;
  late DatabaseService _dbService;
  late ConnectivityService _connectivityService;
  
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  
  File? _imagenSeleccionada;
  String? _fotoActualUrl;
  bool _isLoading = false;
  bool _isOnline = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _dbService = DatabaseService();
    _connectivityService = ConnectivityService();
    _cargarDatos();
  }

  Future<String> _getValidToken() async {
    String token = widget.token;
    if (token.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString('token') ?? '';
    }
    return token;
  }

  void _cargarDatos() {
    _nombreController.text = widget.userData['nombre'] ?? '';
    _fotoActualUrl = widget.userData['foto_perfil_url'] ?? widget.userData['fotoPerfilUrl'];
    _verificarConexion();
  }

  Future<void> _verificarConexion() async {
    final hasInternet = await _connectivityService.hasInternet();
    setState(() {
      _isOnline = hasInternet;
    });
  }

  Future<void> _seleccionarImagen() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _imagenSeleccionada = File(pickedFile.path);
      });
    }
  }

  Future<void> _tomarFoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      setState(() {
        _imagenSeleccionada = File(pickedFile.path);
      });
    }
  }

  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (!_isOnline) {
      _showSnack('Sin conexión a internet. Conéctate para actualizar tu perfil.', isError: true);
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
      
      final String? nombre = _nombreController.text.trim().isNotEmpty 
          ? _nombreController.text.trim() 
          : null;
      
      final response = await _apiService.editarPerfil(
        token,
        nombre: nombre,
        fotoPerfil: _imagenSeleccionada,
      );
      
      if (response['success']) {
        await _actualizarCacheLocal(nombre);
        _showSnack(response['message']);
        Navigator.pop(context, true);
      } else {
        setState(() {
          _errorMessage = response['message'] ?? 'Error al actualizar perfil';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error de conexión: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _actualizarCacheLocal(String? nuevoNombre) async {
    try {
      final usuarioCache = await _dbService.getUsuarioCache();
      if (usuarioCache != null) {
        if (nuevoNombre != null && nuevoNombre.isNotEmpty) {
          usuarioCache['nombre'] = nuevoNombre;
        }
        await _dbService.guardarUsuario(usuarioCache);
      }
    } catch (e) {
      if (kDebugMode) print('Error actualizando caché: $e');
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppTheme.error : AppTheme.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _mostrarOpcionesImagen() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Foto de perfil',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Icon(Icons.photo_library, color: AppTheme.green),
                title: const Text('Galería', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _seleccionarImagen();
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt, color: AppTheme.green),
                title: const Text('Cámara', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _tomarFoto();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool tieneFotoActual = _fotoActualUrl != null && _fotoActualUrl!.isNotEmpty;

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: const Text('Editar Perfil', style: TextStyle(color: AppTheme.textPrimary)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (!_isOnline)
            Container(
              margin: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  Icon(Icons.wifi_off, size: 16, color: AppTheme.warning),
                  const SizedBox(width: 4),
                  Text('Offline', style: TextStyle(fontSize: 12, color: AppTheme.warning)),
                ],
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Foto de perfil
              Center(
                child: Stack(
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.green, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.green.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: _imagenSeleccionada != null
                            ? Image.file(
                                _imagenSeleccionada!,
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                              )
                            : (tieneFotoActual
                                ? CachedNetworkImage(
                                    imageUrl: _fotoActualUrl!,
                                    width: 120,
                                    height: 120,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                    errorWidget: (context, url, error) => Icon(
                                      Icons.person,
                                      size: 60,
                                      color: AppTheme.textSecondary,
                                    ),
                                  )
                                : Icon(
                                    Icons.person,
                                    size: 60,
                                    color: AppTheme.textSecondary,
                                  )),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.green,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.green.withOpacity(0.4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                          onPressed: _isOnline ? _mostrarOpcionesImagen : null,
                          tooltip: 'Cambiar foto',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Campo nombre
              TextFormField(
                controller: _nombreController,
                enabled: _isOnline,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Nombre completo',
                  hintText: 'Ingresa tu nombre',
                  prefixIcon: Icon(Icons.person, color: AppTheme.green),
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
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Ingresa tu nombre';
                  }
                  if (value.length < 3) {
                    return 'El nombre debe tener al menos 3 caracteres';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 16),
              
              // Email (solo lectura)
              TextFormField(
                initialValue: widget.userData['email'] ?? '',
                readOnly: true,
                style: const TextStyle(color: AppTheme.textSecondary),
                decoration: InputDecoration(
                  labelText: 'Correo electrónico',
                  prefixIcon: Icon(Icons.email, color: AppTheme.green),
                  suffixIcon: Icon(Icons.lock, color: AppTheme.textSecondary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Botón guardar
              if (_isOnline)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _guardarCambios,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Guardar Cambios', style: TextStyle(fontSize: 16)),
                  ),
                ),
              
              if (!_isOnline)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.warningBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.warning),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off, color: AppTheme.warning),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Sin conexión a internet. Conéctate para editar tu perfil.',
                          style: TextStyle(color: AppTheme.warning),
                        ),
                      ),
                    ],
                  ),
                ),
              
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.errorBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.error),
                  ),
                  child: Text(
                    _errorMessage,
                    style: TextStyle(color: AppTheme.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nombreController.dispose();
    super.dispose();
  }
}
