// lib/screens/forgot_password_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  @override
  _ForgotPasswordScreenState createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  // Para el código de 6 dígitos
  List<TextEditingController> _codeControllers = [];
  List<FocusNode> _codeFocusNodes = [];
  String _verificationCode = '';
  
  bool _isLoading = false;
  bool _codeSent = false;
  String _errorMessage = '';
  String _successMessage = '';
  
  late ApiService _apiService;
  
  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _initCodeFields();
  }
  
  void _initCodeFields() {
    for (int i = 0; i < 6; i++) {
      _codeControllers.add(TextEditingController());
      _codeFocusNodes.add(FocusNode());
    }
  }
  
  void _onCodeChanged(String value, int index) {
    if (value.length == 1 && index < 5) {
      // Auto-focus al siguiente campo
      FocusScope.of(context).requestFocus(_codeFocusNodes[index + 1]);
    } else if (value.isEmpty && index > 0) {
      // Auto-focus al campo anterior si se borra
      FocusScope.of(context).requestFocus(_codeFocusNodes[index - 1]);
    }
    
    // Actualizar el código completo
    _verificationCode = _codeControllers.map((c) => c.text).join();
  }

  Future<void> _sendRecoveryCode() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _successMessage = '';
    });
    
    try {
      final response = await _apiService.forgotPassword(
        _emailController.text.trim(),
      );
      
      if (!mounted) return;
      
      if (response['success']) {
        setState(() {
          _codeSent = true;
          _successMessage = response['message'] ?? '¡Código de verificación enviado a tu correo!';
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response['message'] ?? 'Error al enviar el código';
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
  
  Future<void> _resetPassword() async {
    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = 'Las contraseñas no coinciden');
      return;
    }
    
    // Validar que el código tenga 6 dígitos
    if (_verificationCode.length != 6) {
      setState(() => _errorMessage = 'Ingresa el código de 6 dígitos completo');
      return;
    }
    
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _successMessage = '';
    });
    
    try {
      final response = await _apiService.resetPassword(
        _emailController.text.trim(),
        _verificationCode,
        _newPasswordController.text.trim(),
      );
      
      if (!mounted) return;
      
      if (response['success']) {
        setState(() {
          _successMessage = response['message'] ?? '¡Contraseña cambiada exitosamente!';
          _isLoading = false;
        });
        
        // Redirigir al login después de 2 segundos
        Future.delayed(Duration(seconds: 2), () {
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/login');
          }
        });
      } else {
        setState(() {
          _errorMessage = response['message'] ?? 'Error al cambiar la contraseña';
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
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Recuperar Contraseña'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.lock_reset,
                size: 80,
                color: Colors.blue,
              ),
              SizedBox(height: 20),
              Text(
                _codeSent ? 'Restablecer Contraseña' : 'Recuperar Contraseña',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 10),
              Text(
                _codeSent 
                    ? 'Ingresa el código de verificación y tu nueva contraseña'
                    : 'Ingresa tu correo electrónico para recibir un código de verificación',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 30),
              
              // Mensajes de error/success
              if (_errorMessage.isNotEmpty)
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Text(
                    _errorMessage,
                    style: TextStyle(color: Colors.red[700]),
                    textAlign: TextAlign.center,
                  ),
                ),
              
              if (_successMessage.isNotEmpty)
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Text(
                    _successMessage,
                    style: TextStyle(color: Colors.green[700]),
                    textAlign: TextAlign.center,
                  ),
                ),
              
              SizedBox(height: 20),
              
              // Campo de email (siempre visible)
              TextFormField(
                controller: _emailController,
                enabled: !_codeSent,
                decoration: InputDecoration(
                  labelText: 'Correo electrónico',
                  prefixIcon: Icon(Icons.email),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Ingresa tu correo electrónico';
                  }
                  if (!value.contains('@') || !value.contains('.')) {
                    return 'Ingresa un correo válido';
                  }
                  return null;
                },
              ),
              
              SizedBox(height: 16),
              
              // Campos del código de verificación (6 cuadros)
              if (_codeSent) ...[
                Text(
                  'Código de verificación',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(6, (index) => _buildCodeTextField(index)),
                ),
                SizedBox(height: 24),
                
                // Campos de nueva contraseña
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Nueva contraseña',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Ingresa tu nueva contraseña';
                    }
                    if (value.length < 6) {
                      return 'La contraseña debe tener al menos 6 caracteres';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Confirmar nueva contraseña',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Confirma tu nueva contraseña';
                    }
                    if (value != _newPasswordController.text) {
                      return 'Las contraseñas no coinciden';
                    }
                    return null;
                  },
                ),
              ],
              
              SizedBox(height: 30),
              
              // Botón principal
              ElevatedButton(
                onPressed: _isLoading ? null : (_codeSent ? _resetPassword : _sendRecoveryCode),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isLoading
                    ? CircularProgressIndicator(color: Colors.white)
                    : Text(
                        _codeSent ? 'Cambiar Contraseña' : 'Enviar Código',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
              
              SizedBox(height: 16),
              
              // Botón para volver al login
              TextButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/login');
                },
                child: Text('Volver al inicio de sesión'),
              ),
              
              // Botón para reenviar código
              if (_codeSent)
                TextButton(
                  onPressed: _isLoading ? null : _sendRecoveryCode,
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
  
  Widget _buildCodeTextField(int index) {
    return Container(
      width: 50,
      height: 60,
      child: TextFormField(
        controller: _codeControllers[index],
        focusNode: _codeFocusNodes[index],
        onChanged: (value) => _onCodeChanged(value, index),
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          counterText: '',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          contentPadding: EdgeInsets.all(12),
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _emailController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    for (var controller in _codeControllers) {
      controller.dispose();
    }
    for (var focusNode in _codeFocusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }
}