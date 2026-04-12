// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import 'manage_employees_screen.dart';
import 'login_screen.dart';
import 'edit_profile_screen.dart';
import 'role_selection_screen.dart';
import 'change_password_screen.dart';
import 'change_email_screen.dart';

class SettingsScreen extends StatefulWidget {
  final String token;

  const SettingsScreen({Key? key, required this.token}) : super(key: key);

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late ApiService _apiService;
  late DatabaseService _dbService;
  late ConnectivityService _connectivityService;
  
  Map<String, dynamic> _userData = {};
  bool _isLoading = true;
  bool _isOnline = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _dbService = DatabaseService();
    _connectivityService = ConnectivityService();
    _checkConnection();
    _loadUserData();
  }

  Future<void> _checkConnection() async {
    final hasInternet = await _connectivityService.hasInternet();
    setState(() {
      _isOnline = hasInternet;
    });
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final hasInternet = await _connectivityService.hasInternet();
    
    if (hasInternet) {
      try {
        final response = await _apiService.getCurrentUser(widget.token);
        if (mounted && response['success']) {
          setState(() {
            _userData = Map<String, dynamic>.from(response['data']);
          });
          await _dbService.guardarUsuario(_userData);
        } else {
          setState(() {
            _errorMessage = response['message'] ?? 'Error al cargar datos';
          });
        }
      } catch (e) {
        print('Error cargando usuario: $e');
        await _loadUserFromCache();
      }
    } else {
      await _loadUserFromCache();
      if (_userData.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Modo offline - Mostrando datos guardados'),
            backgroundColor: AppTheme.warning,
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
    
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUserFromCache() async {
    final usuarioCache = await _dbService.getUsuarioCache();
    if (usuarioCache != null) {
      setState(() {
        _userData = usuarioCache;
      });
    } else {
      setState(() {
        _errorMessage = 'Sin conexión a internet. Conéctate para cargar tus datos.';
      });
    }
  }

  Future<void> _logout() async {
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
              child: const Text('Cerrar Sesión', style: TextStyle(color: AppTheme.error)),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      setState(() {
        _isLoading = true;
      });

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

  void _showOfflineMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Esta opción requiere conexión a internet'),
        backgroundColor: AppTheme.warning,
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
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

  void _navigateToManageEmployees() {
    if (!_isOnline) {
      _showOfflineMessage();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ManageEmployeesScreen(token: widget.token),
      ),
    );
  }

  Future<String> _getValidToken() async {
    String token = widget.token;
    if (token.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString('token') ?? '';
    }
    return token;
  }

  void _confirmarSalirDelNegocio() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Salir del negocio', style: TextStyle(color: AppTheme.textPrimary)),
          content: Text(
            '¿Estás seguro de que deseas salir de este negocio?\n\n'
            'Perderás acceso a todas las transferencias y datos del negocio. '
            'Podrás unirte a otro negocio más tarde.',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppTheme.warning),
              child: Text('Salir', style: TextStyle(color: AppTheme.warning)),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await _salirDelNegocio();
    }
  }

  Future<void> _salirDelNegocio() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final token = await _getValidToken();
      if (token.isEmpty) {
        _showSnack('Sesión expirada. Por favor inicia sesión nuevamente.', isError: true);
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final response = await _apiService.salirDelNegocio(token);

      if (response['success']) {
        _showSnack(response['message']);
        
        await _dbService.limpiarTransferenciasCache();
        
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => RoleSelectionScreen(token: token),
            ),
            (route) => false,
          );
        }
      } else {
        _showSnack(response['message'] ?? 'Error al salir del negocio', isError: true);
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error en _salirDelNegocio: $e');
      _showSnack('Error de conexión: ${e.toString()}', isError: true);
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showBusinessInfoDialog() {
    final negocio = _userData['negocio'] ?? {};
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Información del Negocio', style: TextStyle(color: AppTheme.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nombre:',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
              ),
              Text(_userData['nombre_negocio'] ?? 'No disponible', style: const TextStyle(color: AppTheme.textPrimary)),
              const SizedBox(height: 12),
              Text(
                'Código de invitación:',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
              ),
              SelectableText(
                _userData['codigo_negocio'] ?? 'No disponible',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              if (_userData['es_dueno'] == false) ...[
                const SizedBox(height: 12),
                Text(
                  'Tu rol:',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                ),
                Text(_userData['cargo'] ?? 'Empleado', style: const TextStyle(color: AppTheme.textPrimary)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cerrar', style: TextStyle(color: AppTheme.textSecondary)),
            ),
          ],
        );
      },
    );
  }

  void _copiarCodigo(String codigo) {
    Clipboard.setData(ClipboardData(text: codigo));
    _showSnack('Código copiado al portapapeles');
  }

  void _compartirCodigo(String codigo) async {
    await Share.share(
      '📱 *PillaPago* - Invitación\n\n'
      'Únete a mi negocio usando este código:\n'
      '`$codigo`\n\n'
      'Descarga la app: [link de descarga]',
    );
  }

void _showInvitationCodeDialog() {
  final codigoNegocio = _userData['codigo_negocio'] ?? 'No disponible';

  showDialog(
    context: context,
    builder: (BuildContext context) {
      return Dialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Código de Invitación',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 16),

              // ✅ Contenedor del QR con logo superpuesto en Stack
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 1️⃣ QR sin logo embebido pero con alta corrección de errores
                      QrImageView(
                        data: codigoNegocio,
                        version: QrVersions.auto,
                        size: 200,
                        gapless: false,
                        errorCorrectionLevel: QrErrorCorrectLevel.H,
                        eyeStyle: QrEyeStyle(
                          color: AppTheme.green,
                          eyeShape: QrEyeShape.circle,
                        ),
                        dataModuleStyle: QrDataModuleStyle(
                          color: AppTheme.green,
                          dataModuleShape: QrDataModuleShape.circle,
                        ),
                      ),

                      // 2️⃣ Fondo blanco circular que "borra" el centro del QR
                      Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),

                      // 3️⃣ Logo encima del hueco blanco
                      ClipOval(
                        child: Image.asset(
                          'assets/images/solo logo.png',
                          width: 44,
                          height: 44,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Text(
                'Código:',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                codigoNegocio,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _copiarCodigo(codigoNegocio),
                    icon: Icon(Icons.copy, size: 18, color: AppTheme.green),
                    label: const Text('Copiar'),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppTheme.border),
                      foregroundColor: AppTheme.textPrimary,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _compartirCodigo(codigoNegocio),
                    icon: const Icon(Icons.share, size: 18, color: Colors.white),
                    label: const Text('Compartir'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Column(
            children: [
              Icon(Icons.payment, size: 56, color: AppTheme.green),
              const SizedBox(height: 8),
              const Text(
                'PillaPago',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Versión 1.0.0',
                  style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 16),
                Divider(color: AppTheme.border),
                const SizedBox(height: 16),
                const Text(
                  'Registro de Transferencias',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.green),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Registra tus transferencias bancarias de forma rápida y sencilla.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 12),
                Text(
                  '✓ Registro de transferencias\n✓ Almacenamiento offline\n✓ Sincronización automática\n✓ Historial de transacciones',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 16),
                Divider(color: AppTheme.border),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.developer_mode, size: 16, color: AppTheme.green),
                    const SizedBox(width: 8),
                    const Text(
                      'Desarrollado por MutanTech',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '© 2024 MutanTech. Todos los derechos reservados.',
                  style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cerrar', style: TextStyle(color: AppTheme.green)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final String fotoPerfilUrl = _userData['foto_perfil_url'] ?? _userData['fotoPerfilUrl'] ?? '';
    final bool tieneFoto = _userData['tiene_foto_perfil'] ?? false;
    final bool esDueno = _userData['es_dueno'] ?? false;

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: Row(
          children: [
            const Text("Configuración", style: TextStyle(color: AppTheme.textPrimary)),
            const SizedBox(width: 8),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isOnline ? AppTheme.green : AppTheme.error,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: AppTheme.error),
                      const SizedBox(height: 16),
                      Text(_errorMessage, style: const TextStyle(color: AppTheme.error)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadUserData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.green,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      // Perfil
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Card(
                          color: AppTheme.surfaceLight,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: AppTheme.border.withOpacity(0.5), width: 1),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                _buildProfileImage(fotoPerfilUrl, tieneFoto, _userData['nombre']),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _userData['nombre'] ?? 'Usuario',
                                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _userData['email'] ?? 'Sin email',
                                        style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: esDueno ? AppTheme.green.withOpacity(0.2) : AppTheme.warning.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          esDueno ? 'Dueño' : 'Empleado',
                                          style: TextStyle(
                                            color: esDueno ? AppTheme.green : AppTheme.warning,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      
                      // Opciones de configuración
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // Editar Perfil
                            Card(
                              color: AppTheme.surface,
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.green.withOpacity(0.2),
                                  child: Icon(Icons.person, color: AppTheme.green),
                                ),
                                title: const Text('Editar Perfil', style: TextStyle(color: AppTheme.textPrimary)),
                                subtitle: const Text('Cambiar nombre, foto de perfil', style: TextStyle(color: AppTheme.textSecondary)),
                                trailing: Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                                onTap: () async {
                                  if (!_isOnline) {
                                    _showOfflineMessage();
                                    return;
                                  }
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => EditProfileScreen(
                                        token: widget.token,
                                        userData: _userData,
                                      ),
                                    ),
                                  );
                                  if (result == true) {
                                    await _loadUserData();
                                  }
                                },
                              ),
                            ),
                            
                            const SizedBox(height: 12),
                            
                            // Cambiar Contraseña
                            if (_userData['google_id'] == null)
                              Card(
                                color: AppTheme.surface,
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppTheme.warning.withOpacity(0.2),
                                    child: Icon(Icons.lock, color: AppTheme.warning),
                                  ),
                                  title: const Text('Cambiar Contraseña', style: TextStyle(color: AppTheme.textPrimary)),
                                  subtitle: const Text('Actualizar tu contraseña', style: TextStyle(color: AppTheme.textSecondary)),
                                  trailing: Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                                  onTap: () async {
                                    if (!_isOnline) {
                                      _showOfflineMessage();
                                      return;
                                    }
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ChangePasswordScreen(token: widget.token),
                                      ),
                                    );
                                    if (result == true) {
                                      _showSnack('Contraseña actualizada correctamente');
                                    }
                                  },
                                ),
                              ),
                            
                            // Cambiar Correo
                            if (_userData['google_id'] == null)
                              Card(
                                color: AppTheme.surface,
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppTheme.green.withOpacity(0.2),
                                    child: Icon(Icons.email, color: AppTheme.green),
                                  ),
                                  title: const Text('Cambiar Correo', style: TextStyle(color: AppTheme.textPrimary)),
                                  subtitle: const Text('Actualizar tu correo electrónico', style: TextStyle(color: AppTheme.textSecondary)),
                                  trailing: Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                                  onTap: () async {
                                    if (!_isOnline) {
                                      _showOfflineMessage();
                                      return;
                                    }
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ChangeEmailScreen(
                                          token: widget.token,
                                          currentEmail: _userData['email'] ?? '',
                                        ),
                                      ),
                                    );
                                    if (result == true) {
                                      await _loadUserData();
                                      _showSnack('Correo actualizado correctamente');
                                    }
                                  },
                                ),
                              ),
                            
                            if (_userData['google_id'] == null)
                              const SizedBox(height: 12),
                            
                            // Información del Negocio
                            Card(
                              color: AppTheme.surface,
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.green.withOpacity(0.2),
                                  child: Icon(Icons.business, color: AppTheme.green),
                                ),
                                title: const Text('Información del Negocio', style: TextStyle(color: AppTheme.textPrimary)),
                                subtitle: const Text('Ver detalles de tu negocio', style: TextStyle(color: AppTheme.textSecondary)),
                                trailing: Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                                onTap: _showBusinessInfoDialog,
                              ),
                            ),
                            
                            const SizedBox(height: 12),
                            
                            // Gestionar Empleados
                            if (esDueno)
                              Card(
                                color: AppTheme.surface,
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppTheme.green.withOpacity(0.2),
                                    child: Icon(Icons.people, color: AppTheme.green),
                                  ),
                                  title: const Text('Gestionar Empleados', style: TextStyle(color: AppTheme.textPrimary)),
                                  subtitle: const Text('Ver y administrar empleados', style: TextStyle(color: AppTheme.textSecondary)),
                                  trailing: Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                                  onTap: _navigateToManageEmployees,
                                ),
                              ),
                            
                            if (esDueno) const SizedBox(height: 12),
                            
                            // Compartir Código
                            if (esDueno)
                              Card(
                                color: AppTheme.surface,
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppTheme.green.withOpacity(0.2),
                                    child: Icon(Icons.share, color: AppTheme.green),
                                  ),
                                  title: const Text('Compartir Código', style: TextStyle(color: AppTheme.textPrimary)),
                                  subtitle: const Text('Invitar empleados a tu negocio', style: TextStyle(color: AppTheme.textSecondary)),
                                  trailing: Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                                  onTap: _showInvitationCodeDialog,
                                ),
                              ),
                            
                            if (esDueno) const SizedBox(height: 12),
                            
                            // Salir del negocio
                            Card(
                              color: AppTheme.surface,
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.warning.withOpacity(0.2),
                                  child: Icon(Icons.exit_to_app, color: AppTheme.warning),
                                ),
                                title: Text(
                                  'Salir del negocio',
                                  style: TextStyle(color: AppTheme.warning),
                                ),
                                subtitle: Text(
                                  'Dejar de pertenecer a este negocio',
                                  style: TextStyle(color: AppTheme.warning),
                                ),
                                trailing: Icon(Icons.chevron_right, color: AppTheme.warning),
                                onTap: _confirmarSalirDelNegocio,
                              ),
                            ),
                            
                            const SizedBox(height: 12),
                            
                            // Cerrar Sesión
                            Card(
                              color: AppTheme.surface,
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.error.withOpacity(0.2),
                                  child: Icon(Icons.logout, color: AppTheme.error),
                                ),
                                title: Text(
                                  'Cerrar Sesión',
                                  style: TextStyle(color: AppTheme.error),
                                ),
                                subtitle: Text(
                                  'Salir de tu cuenta',
                                  style: TextStyle(color: AppTheme.error),
                                ),
                                trailing: Icon(Icons.chevron_right, color: AppTheme.error),
                                onTap: _logout,
                              ),
                            ),
                            
                            const SizedBox(height: 24),
                            
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
                                        'Modo offline. Algunas opciones están deshabilitadas.',
                                        style: TextStyle(color: AppTheme.warning),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            
                            const SizedBox(height: 24),
                            
                            // Acerca de
                            Card(
                              color: Colors.transparent,
                              elevation: 0,
                              child: Column(
                                children: [
                                  Divider(color: AppTheme.border),
                                  const SizedBox(height: 16),
                                  ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: AppTheme.green.withOpacity(0.2),
                                      child: Icon(Icons.info_outline, color: AppTheme.green),
                                    ),
                                    title: const Text('Acerca de', style: TextStyle(color: AppTheme.textPrimary)),
                                    subtitle: const Text('Información de la aplicación', style: TextStyle(color: AppTheme.textSecondary)),
                                    trailing: Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                                    onTap: _showAboutDialog,
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: Column(
                                      children: [
                                        Text(
                                          'Desarrollado por',
                                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'MutanTech',
                                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.green),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'mutantech.dev@gmail.com',
                                          style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildProfileImage(String fotoUrl, bool tieneFoto, String? nombre) {
    final double size = 80;
    
    if (tieneFoto && fotoUrl.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: fotoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            width: size,
            height: size,
            child: const CircularProgressIndicator(),
          ),
          errorWidget: (context, url, error) => CircleAvatar(
            radius: size / 2,
            backgroundColor: AppTheme.surfaceLight,
            child: Text(
              nombre?.substring(0, 1).toUpperCase() ?? 'U',
              style: TextStyle(fontSize: size / 2, fontWeight: FontWeight.bold, color: AppTheme.green),
            ),
          ),
        ),
      );
    } else {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: AppTheme.surfaceLight,
        child: Text(
          nombre?.substring(0, 1).toUpperCase() ?? 'U',
          style: TextStyle(fontSize: size / 2, fontWeight: FontWeight.bold, color: AppTheme.green),
        ),
      );
    }
  }
}