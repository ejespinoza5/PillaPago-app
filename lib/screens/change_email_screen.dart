// lib/screens/change_email_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/connectivity_service.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';

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
  
  // ✅ Código con cuadros separados
  final List<TextEditingController> _codeControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _codeFocusNodes = List.generate(6, (_) => FocusNode());
  
  bool _isLoading = false;
  bool _isOnline = true;
  bool _codeSent = false;
  String _errorMessage = '';
  String _successMessage = '';

  String get _code => _codeControllers.map((c) => c.text).join();

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _connectivityService = ConnectivityService();
    _dbService = DatabaseService();
    _verificarConexion();
  }

  @override
  void dispose() {
    _newEmailController.dispose();
    for (var c in _codeControllers) c.dispose();
    for (var f in _codeFocusNodes) f.dispose();
    super.dispose();
  }

  void _onCodeChanged(String value, int index) {
    if (value.length == 1 && index < 5) {
      _codeFocusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _codeFocusNodes[index - 1].requestFocus();
    }
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
    if (_code.length < 6) {
      _showSnack('Ingresa los 6 dígitos del código de verificación', isError: true);
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
        code: _code,
      );
      
      if (response['success']) {
        await _actualizarEmailEnCache(_newEmailController.text.trim());
        _showSnack(response['message']);
        
        Future.delayed(const Duration(seconds: 1), () {
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
      }
    } catch (e) {
      print('Error actualizando email en caché: $e');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: const Text('Cambiar Correo Electrónico', style: TextStyle(color: AppTheme.textPrimary)),
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
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.email,
                size: 80,
                color: AppTheme.green,
              ),
              const SizedBox(height: 20),
              
              Text(
                _codeSent ? 'Verificar Código' : 'Cambiar Correo',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _codeSent 
                    ? 'Ingresa el código de verificación enviado a tu nuevo correo'
                    : 'Ingresa tu nuevo correo electrónico',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              
              // Correo actual (solo lectura)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.email, color: AppTheme.textSecondary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Correo actual',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.currentEmail,
                            style: const TextStyle(color: AppTheme.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Nuevo correo
              if (!_codeSent)
                TextFormField(
                  controller: _newEmailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Nuevo correo electrónico',
                    hintText: 'Ingresa tu nuevo correo',
                    prefixIcon: Icon(Icons.email_outlined, color: AppTheme.green),
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
              
              // ✅ Código de verificación con cuadros separados
              if (_codeSent) ...[
                const Text(
                  'Código de verificación',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(6, (index) => _buildCodeTextField(index)),
                ),
                
                // ✅ Mensaje para revisar SPAM
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.warningBg.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.warning.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.mark_email_unread, size: 20, color: AppTheme.warning),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          ' ¿No encuentras el correo? Revisa tu carpeta de SPAM o correo no deseado',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.warning,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              const SizedBox(height: 24),
              
              if (_errorMessage.isNotEmpty)
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
              
              if (_successMessage.isNotEmpty && !_codeSent)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.successBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.success),
                  ),
                  child: Text(
                    _successMessage,
                    style: TextStyle(color: AppTheme.success),
                    textAlign: TextAlign.center,
                  ),
                ),
              
              const SizedBox(height: 16),
              
              if (_isOnline)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : (_codeSent ? _confirmarCambio : _solicitarCodigo),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _codeSent ? AppTheme.green : AppTheme.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            _codeSent ? 'Confirmar Cambio' : 'Enviar Código',
                            style: const TextStyle(fontSize: 16),
                          ),
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
                          'Sin conexión a internet. Conéctate para cambiar tu correo.',
                          style: TextStyle(color: AppTheme.warning),
                        ),
                      ),
                    ],
                  ),
                ),
              
              if (_codeSent && !_isLoading)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: TextButton(
                    onPressed: _solicitarCodigo,
                    child: Text(
                      '¿No recibiste el código? Reenviar',
                      style: TextStyle(color: AppTheme.green),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCodeTextField(int index) {
    return SizedBox(
      width: 48,
      height: 60,
      child: TextFormField(
        controller: _codeControllers[index],
        focusNode: _codeFocusNodes[index],
        onChanged: (value) => _onCodeChanged(value, index),
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        decoration: InputDecoration(
          counterText: '',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.green, width: 2),
          ),
          contentPadding: const EdgeInsets.all(12),
        ),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
    );
  }
}