// lib/screens/edit_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  print('Token en edit_profile: ${token.length} caracteres');
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
    // ✅ Usar _getValidToken() en lugar de widget.token
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
      token,  // ✅ Usar el token validado
      nombre: nombre,
      fotoPerfil: _imagenSeleccionada,
    );
    
    if (response['success']) {
      // Actualizar caché local
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
      print('✅ Caché local actualizada');
    }
  } catch (e) {
    print('Error actualizando caché: $e');
  }
}

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool tieneFotoActual = _fotoActualUrl != null && _fotoActualUrl!.isNotEmpty;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Editar Perfil'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          if (!_isOnline)
            Container(
              margin: EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  Icon(Icons.wifi_off, size: 16, color: Colors.white),
                  SizedBox(width: 4),
                  Text('Offline', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Foto de perfil actual
              Center(
                child: Stack(
                  children: [
                    // Foto actual o nueva
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.blue, width: 3),
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
                                    placeholder: (context, url) => 
                                        Center(child: CircularProgressIndicator()),
                                    errorWidget: (context, url, error) => 
                                        Icon(Icons.person, size: 60, color: Colors.grey),
                                  )
                                : Icon(Icons.person, size: 60, color: Colors.grey)),
                      ),
                    ),
                    // Botón para cambiar foto
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: Icon(Icons.camera_alt, color: Colors.white, size: 20),
                          onPressed: _isOnline ? _mostrarOpcionesImagen : null,
                          tooltip: 'Cambiar foto',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 24),
              
              // Campo de nombre
              TextFormField(
                controller: _nombreController,
                enabled: _isOnline,
                decoration: InputDecoration(
                  labelText: 'Nombre completo',
                  hintText: 'Ingresa tu nombre',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
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
              
              SizedBox(height: 16),
              
              // Email (solo lectura)
              TextFormField(
                initialValue: widget.userData['email'] ?? '',
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Correo electrónico',
                  prefixIcon: Icon(Icons.email),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  suffixIcon: Icon(Icons.lock, color: Colors.grey),
                ),
              ),
              
              SizedBox(height: 24),
              
              // Botón guardar
              if (_isOnline)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _guardarCambios,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text('Guardar Cambios', style: TextStyle(fontSize: 16)),
                  ),
                ),
              
              if (!_isOnline)
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off, color: Colors.orange),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Sin conexión a internet. Conéctate para editar tu perfil.',
                          style: TextStyle(color: Colors.orange.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
              
              if (_errorMessage.isNotEmpty) ...[
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    _errorMessage,
                    style: TextStyle(color: Colors.red.shade700),
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

  void _mostrarOpcionesImagen() {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.photo_library, color: Colors.blue),
                title: Text('Galería'),
                onTap: () {
                  Navigator.pop(context);
                  _seleccionarImagen();
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt, color: Colors.blue),
                title: Text('Cámara'),
                onTap: () {
                  Navigator.pop(context);
                  _tomarFoto();
                },
              ),
              ListTile(
                leading: Icon(Icons.delete, color: Colors.red),
                title: Text('Eliminar foto actual', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _imagenSeleccionada = null;
                    _fotoActualUrl = null;
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _nombreController.dispose();
    super.dispose();
  }
}