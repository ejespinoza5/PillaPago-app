// lib/screens/change_email_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/connectivity_service.dart';
import '../services/database_service.dart';

class ChangeEmailScreen extends StatefulWidget {
  final String token;
  final String currentEmail;

  const ChangeEmailScreen({
    Key? key,
    required this.token,
    required this.currentEmail,
  }) : super(key: key);

  @override
  _ChangeEmailScreenState createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends State<ChangeEmailScreen> {
  late ApiService _apiService;
  late ConnectivityService _connectivityService;
  late DatabaseService _dbService;
  
  final _formKey = GlobalKey<FormState>();
  final _newEmailController = TextEditingController();
  final _codeController = TextEditingController();
  
  bool _isLoading = false;
  bool _isOnline = true;
  bool _codeSent = false;
  String _errorMessage = '';
  String _successMessage = '';

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _connectivityService = ConnectivityService();
    _dbService = DatabaseService();
    _verificarConexion();
  }

  Future<void> _verificarConexion() async {
    final hasInternet = await _connectivityService.hasInternet();
    setState(() {
      _isOnline = hasInternet;
    });
  }

  Future<String> _getValidToken() async {
    String token = widget.token;
    if (token.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString('token') ?? '';
    }
    return token;
  }

  Future<void> _solicitarCodigo() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (!_isOnline) {
      _showSnack('Sin conexión a internet. Conéctate para cambiar tu correo.', isError: true);
      return;
    }
    
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _successMessage = '';
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
      
      final response = await _apiService.solicitarCambioEmail(
        token,
        newEmail: _newEmailController.text.trim(),
      );
      
      if (response['success']) {
        setState(() {
          _codeSent = true;
          _successMessage = response['message'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response['message'];
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

  Future<void> _confirmarCambio() async {
    if (_codeController.text.trim().isEmpty) {
      _showSnack('Ingresa el código de verificación', isError: true);
      return;
    }
    
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _successMessage = '';
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
      
      final response = await _apiService.confirmarCambioEmail(
        token,
        newEmail: _newEmailController.text.trim(),
        code: _codeController.text.trim(),
      );
      
      if (response['success']) {
        // Actualizar caché local
        await _actualizarEmailEnCache(_newEmailController.text.trim());
        
        _showSnack(response['message']);
        
        // Regresar a la pantalla anterior después de 1.5 segundos
        Future.delayed(Duration(seconds: 1), () {
          if (mounted) {
            Navigator.pop(context, true);
          }
        });
      } else {
        setState(() {
          _errorMessage = response['message'];
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

  Future<void> _actualizarEmailEnCache(String newEmail) async {
    try {
      final usuarioCache = await _dbService.getUsuarioCache();
      if (usuarioCache != null) {
        usuarioCache['email'] = newEmail;
        await _dbService.guardarUsuario(usuarioCache);
        print('✅ Email actualizado en caché local');
      }
    } catch (e) {
      print('Error actualizando email en caché: $e');
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
    return Scaffold(
      appBar: AppBar(
        title: Text('Cambiar Correo Electrónico'),
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
        padding: EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icono
              Icon(
                Icons.email,
                size: 80,
                color: Colors.blue,
              ),
              SizedBox(height: 20),
              
              // Título
              Text(
                _codeSent ? 'Verificar Código' : 'Cambiar Correo',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                _codeSent 
                    ? 'Ingresa el código de verificación enviado a tu nuevo correo'
                    : 'Ingresa tu nuevo correo electrónico',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 30),
              
              // Correo actual (solo lectura)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.email, color: Colors.grey),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Correo actual',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            widget.currentEmail,
                            style: TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 20),
              
              // Nuevo correo
              if (!_codeSent)
                TextFormField(
                  controller: _newEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Nuevo correo electrónico',
                    hintText: 'Ingresa tu nuevo correo',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Ingresa tu nuevo correo';
                    }
                    if (!value.contains('@') || !value.contains('.')) {
                      return 'Ingresa un correo válido';
                    }
                    if (value == widget.currentEmail) {
                      return 'El nuevo correo debe ser diferente al actual';
                    }
                    return null;
                  },
                ),
              
              // Código de verificación
              if (_codeSent)
                TextFormField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Código de verificación',
                    hintText: 'Ingresa el código de 6 dígitos',
                    prefixIcon: Icon(Icons.vpn_key),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              
              SizedBox(height: 24),
              
              // Mensajes
              if (_errorMessage.isNotEmpty)
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
              
              if (_successMessage.isNotEmpty && !_codeSent)
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Text(
                    _successMessage,
                    style: TextStyle(color: Colors.green.shade700),
                    textAlign: TextAlign.center,
                  ),
                ),
              
              SizedBox(height: 16),
              
              // Botón principal
              if (_isOnline)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : (_codeSent ? _confirmarCambio : _solicitarCodigo),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _codeSent ? Colors.green : Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text(
                            _codeSent ? 'Confirmar Cambio' : 'Enviar Código',
                            style: TextStyle(fontSize: 16),
                          ),
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
                          'Sin conexión a internet. Conéctate para cambiar tu correo.',
                          style: TextStyle(color: Colors.orange.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
              
              // Botón para reenviar código
              if (_codeSent && !_isLoading)
                TextButton(
                  onPressed: _solicitarCodigo,
                  child: Text(
                    '¿No recibiste el código? Reenviar',
                    style: TextStyle(color: Colors.blue),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _newEmailController.dispose();
    _codeController.dispose();
    super.dispose();
  }
}