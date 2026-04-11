import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import 'role_selection_screen.dart';
import 'login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VerifyEmailScreen extends StatefulWidget {
  final String email;
  final String? token; // ✅ Agregar token

  const VerifyEmailScreen({super.key, required this.email, this.token});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  bool _isResending = false;
  String _errorMessage = '';
  String _successMessage = '';

  String get _code => _controllers.map((c) => c.text).join();

  @override
  void dispose() {
    for (var c in _controllers) c.dispose();
    for (var f in _focusNodes) f.dispose();
    super.dispose();
  }

  Future<void> _verifyCode() async {
    if (_code.length < 6) {
      setState(() => _errorMessage = 'Ingresa los 6 dígitos del código');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _successMessage = '';
    });

    try {
      // ✅ Pasar el token
      final result = await ApiService.verifyEmail(
        widget.email, 
        _code,
        token: widget.token,
      );

      print('Resultado verifyEmail: $result');

      if (mounted) {
        setState(() => _isLoading = false);

        if (result['success']) {
          _showSnack('¡Correo verificado exitosamente!');
          
          final token = result['token'] ?? widget.token;
          if (token != null && token.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString("token", token);
            
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => RoleSelectionScreen(token: token),
                ),
              );
            }
          } else {
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => LoginScreen(),
                ),
              );
            }
          }
        } else {
          setState(() => _errorMessage = result['message'] ?? 'Código incorrecto');
        }
      }
    } catch (e) {
      print('Error en _verifyCode: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error de conexión: ${e.toString()}';
      });
    }
  }

  Future<void> _resendCode() async {
    setState(() {
      _isResending = true;
      _errorMessage = '';
      _successMessage = '';
    });

    try {
      // ✅ Pasar el token también para reenviar
      final result = await ApiService.resendVerificationCode(
        widget.email,
        token: widget.token,
      );
      
      if (mounted) {
        setState(() => _isResending = false);
        
        if (result['success']) {
          setState(() => _successMessage = result['message'] ?? 'Código reenviado exitosamente');
        } else {
          setState(() => _errorMessage = result['message'] ?? 'Error al reenviar el código');
        }
      }
    } catch (e) {
      print('Error en _resendCode: $e');
      setState(() {
        _isResending = false;
        _errorMessage = 'Error de conexión: ${e.toString()}';
      });
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

  void _onDigitChanged(String value, int index) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verificar correo'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mark_email_read_outlined,
                size: 72, color: Colors.blue),
            const SizedBox(height: 16),
            const Text(
              'Revisa tu correo',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Enviamos un código de 6 dígitos a\n${widget.email}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(6, (index) {
                return SizedBox(
                  width: 48,
                  child: TextField(
                    controller: _controllers[index],
                    focusNode: _focusNodes[index],
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    maxLength: 1,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (value) => _onDigitChanged(value, index),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            if (_errorMessage.isNotEmpty)
              Text(_errorMessage, style: const TextStyle(color: Colors.red)),
            if (_successMessage.isNotEmpty)
              Text(_successMessage, style: const TextStyle(color: Colors.green)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _verifyCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Verificar'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _isResending ? null : _resendCode,
              child: _isResending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Reenviar código'),
            ),
          ],
        ),
      ),
    );
  }
}