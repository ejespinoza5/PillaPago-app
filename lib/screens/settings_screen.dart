// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/connectivity_service.dart';
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
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
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
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
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
  void _showSnack(String msg, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ),
  );
}
void _confirmarSalirDelNegocio() async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text('Salir del negocio'),
        content: Text(
          '¿Estás seguro de que deseas salir de este negocio?\n\n'
          'Perderás acceso a todas las transferencias y datos del negocio. '
          'Podrás unirte a otro negocio más tarde.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: Text('Salir', style: TextStyle(color: Colors.orange)),
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
      
      // ✅ NO limpiar los tokens, solo limpiar la caché del negocio
      // await ApiService.clearTokens();  // ❌ Eliminar esta línea
      
      // Limpiar solo la caché de transferencias y totales
      await _dbService.limpiarTransferenciasCache();
      
      // Navegar a RoleSelectionScreen para elegir un nuevo rol/negocio
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => RoleSelectionScreen(token: token), // ✅ Usar el mismo token
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

Future<String> _getValidToken() async {
  String token = widget.token;
  if (token.isEmpty) {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('token') ?? '';
  }
  return token;
}
  void _showBusinessInfoDialog() {
    final negocio = _userData['negocio'] ?? {};
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Información del Negocio'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nombre:',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700]),
              ),
              Text(_userData['nombre_negocio'] ?? 'No disponible'),
              SizedBox(height: 12),
              Text(
                'Código de invitación:',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700]),
              ),
              SelectableText(
                _userData['codigo_negocio'] ?? 'No disponible',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              if (_userData['es_dueno'] == false) ...[
                SizedBox(height: 12),
                Text(
                  'Tu rol:',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700]),
                ),
                Text(_userData['cargo'] ?? 'Empleado'),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  void _showInvitationCodeDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Código de Invitación'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.business, size: 48, color: Colors.blue),
              SizedBox(height: 16),
              Text(
                'Comparte este código con tus empleados:',
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: SelectableText(
                  _userData['codigo_negocio'] ?? 'No disponible',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  void _showAboutDialog() {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Column(
          children: [
            Icon(Icons.payment, size: 56, color: Colors.blue),
            SizedBox(height: 8),
            Text(
              'PillaPago',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Versión 1.0.0',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: 16),
              Divider(),
              SizedBox(height: 16),
              Text(
                'Registro de Transferencias',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Registra tus transferencias bancarias de forma rápida y sencilla.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 12),
              Text(
                '✓ Registro de transferencias\n✓ Almacenamiento offline\n✓ Sincronización automática\n✓ Historial de transacciones',
                textAlign: TextAlign.left,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              SizedBox(height: 16),
              Divider(),
              SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.developer_mode, size: 16, color: Colors.blue),
                  SizedBox(width: 8),
                  Text(
                    'Desarrollado por MutanTech',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                '© 2024 MutanTech. Todos los derechos reservados.',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[400],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cerrar',
              style: TextStyle(color: Colors.blue),
            ),
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
      appBar: AppBar(
        title: Row(
          children: [
            Text("Configuración"),
            SizedBox(width: 8),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isOnline ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red),
                      SizedBox(height: 16),
                      Text(_errorMessage),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadUserData,
                        child: Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      // Perfil
                      Container(
                        color: Colors.blue.shade50,
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            children: [
                              _buildProfileImage(fotoPerfilUrl, tieneFoto, _userData['nombre']),
                              SizedBox(height: 12),
                              Text(
                                _userData['nombre'] ?? 'Usuario',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                _userData['email'] ?? 'Sin email',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                              SizedBox(height: 8),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: esDueno ? Colors.green.shade100 : Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  esDueno ? 'Dueño' : 'Empleado',
                                  style: TextStyle(
                                    color: esDueno ? Colors.green.shade800 : Colors.orange.shade800,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      // Opciones de configuración
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // Opción: Editar perfil
                            Card(
  elevation: 2,
  child: ListTile(
    leading: CircleAvatar(
      backgroundColor: Colors.blue.shade100,
      child: Icon(Icons.person, color: Colors.blue),
    ),
    title: Text('Editar Perfil'),
    subtitle: Text('Cambiar nombre, foto de perfil'),
    trailing: Icon(Icons.chevron_right),
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
        await _loadUserData(); // Recargar datos después de editar
      }
    },
  ),
),
                            
                            SizedBox(height: 12),
                            
                            // Opción: Cambiar contraseña (solo para usuarios con email/password)
if (_userData['google_id'] == null)
  Card(
    elevation: 2,
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.orange.shade100,
        child: Icon(Icons.lock, color: Colors.orange),
      ),
      title: Text('Cambiar Contraseña'),
      subtitle: Text('Actualizar tu contraseña'),
      trailing: Icon(Icons.chevron_right),
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
          // Si se cambió la contraseña, mostrar mensaje
          _showSnack('Contraseña actualizada correctamente');
        }
      },
    ),
  ),
  // Opción: Cambiar Correo (solo para usuarios con email/password)
if (_userData['google_id'] == null)
  Card(
    elevation: 2,
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.purple.shade100,
        child: Icon(Icons.email, color: Colors.purple),
      ),
      title: Text('Cambiar Correo'),
      subtitle: Text('Actualizar tu correo electrónico'),
      trailing: Icon(Icons.chevron_right),
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
          await _loadUserData(); // Recargar datos
          _showSnack('Correo actualizado correctamente');
        }
      },
    ),
  ),
                            
                            if (_userData['google_id'] == null)
                              SizedBox(height: 12),
                            
                            // Opción: Información del negocio
                            Card(
                              elevation: 2,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.green.shade100,
                                  child: Icon(Icons.business, color: Colors.green),
                                ),
                                title: Text('Información del Negocio'),
                                subtitle: Text('Ver detalles de tu negocio'),
                                trailing: Icon(Icons.chevron_right),
                                onTap: _showBusinessInfoDialog,
                              ),
                            ),
                            
                            SizedBox(height: 12),
                            
                            // Opción: Gestionar Empleados
                            if (esDueno)
                              Card(
                                elevation: 2,
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.teal.shade100,
                                    child: Icon(Icons.people, color: Colors.teal),
                                  ),
                                  title: Text('Gestionar Empleados'),
                                  subtitle: Text('Ver y administrar empleados'),
                                  trailing: Icon(Icons.chevron_right),
                                  onTap: _navigateToManageEmployees,
                                ),
                              ),
                            
                            if (esDueno) SizedBox(height: 12),
                            
                            // Opción: Compartir código
                            if (esDueno)
                              Card(
                                elevation: 2,
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.purple.shade100,
                                    child: Icon(Icons.share, color: Colors.purple),
                                  ),
                                  title: Text('Compartir Código'),
                                  subtitle: Text('Invitar empleados a tu negocio'),
                                  trailing: Icon(Icons.chevron_right),
                                  onTap: _showInvitationCodeDialog,
                                ),
                              ),
                            
                            if (esDueno) SizedBox(height: 12),
                            // Opción: Salir del negocio
Card(
  elevation: 2,
  color: Colors.orange.shade50,
  child: ListTile(
    leading: CircleAvatar(
      backgroundColor: Colors.orange.shade100,
      child: Icon(Icons.exit_to_app, color: Colors.orange),
    ),
    title: Text(
      'Salir del negocio',
      style: TextStyle(color: Colors.orange.shade800),
    ),
    subtitle: Text(
      'Dejar de pertenecer a este negocio',
      style: TextStyle(color: Colors.orange.shade700),
    ),
    trailing: Icon(Icons.chevron_right, color: Colors.orange),
    onTap: _confirmarSalirDelNegocio,
  ),
),

SizedBox(height: 12),
                            // Opción: Cerrar sesión
                            Card(
                              elevation: 2,
                              color: Colors.red.shade50,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.red.shade100,
                                  child: Icon(Icons.exit_to_app, color: Colors.red),
                                ),
                                title: Text(
                                  'Cerrar Sesión',
                                  style: TextStyle(color: Colors.red),
                                ),
                                subtitle: Text(
                                  'Salir de tu cuenta',
                                  style: TextStyle(color: Colors.red.shade700),
                                ),
                                trailing: Icon(Icons.chevron_right, color: Colors.red),
                                onTap: _logout,
                              ),
                            ),
                            
                            SizedBox(height: 24),
                            
                            // Indicador de modo offline
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
                                        'Modo offline. Algunas opciones están deshabilitadas.',
                                        style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            
                            SizedBox(height: 24),
                            
                            // Versión de la app y Acerca de
                            Card(
                              elevation: 0,
                              color: Colors.transparent,
                              child: Column(
                                children: [
                                  Divider(color: Colors.grey.shade300),
                                  SizedBox(height: 16),
                                  // Acerca de
                                  ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.grey.shade200,
                                      child: Icon(Icons.info_outline, color: Colors.blue),
                                    ),
                                    title: Text(
                                      'Acerca de',
                                      style: TextStyle(fontWeight: FontWeight.w500),
                                    ),
                                    subtitle: Text('Información de la aplicación'),
                                    trailing: Icon(Icons.chevron_right, color: Colors.grey),
                                    onTap: _showAboutDialog,
                                  ),
                                  SizedBox(height: 8),
                                  // Desarrollado por
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: Column(
                                      children: [
                                        Text(
                                          'Desarrollado por',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'MutanTech',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue.shade700,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'mutantech.dev@gmail.com',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey[400],
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
            child: CircularProgressIndicator(),
          ),
          errorWidget: (context, url, error) => CircleAvatar(
            radius: size / 2,
            backgroundColor: Colors.blue.shade100,
            child: Text(
              nombre?.substring(0, 1).toUpperCase() ?? 'U',
              style: TextStyle(
                fontSize: size / 2,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade800,
              ),
            ),
          ),
        ),
      );
    } else {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: Colors.blue.shade100,
        child: Text(
          nombre?.substring(0, 1).toUpperCase() ?? 'U',
          style: TextStyle(
            fontSize: size / 2,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade800,
          ),
        ),
      );
    }
  }
}