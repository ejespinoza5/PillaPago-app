// lib/screens/manage_employees_screen.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class ManageEmployeesScreen extends StatefulWidget {
  final String token;

  const ManageEmployeesScreen({Key? key, required this.token}) : super(key: key);

  @override
  _ManageEmployeesScreenState createState() => _ManageEmployeesScreenState();
}

class _ManageEmployeesScreenState extends State<ManageEmployeesScreen>
    with SingleTickerProviderStateMixin {
  late ApiService _apiService;
  late TabController _tabController;
  
  List<dynamic> _empleadosActivos = [];
  List<dynamic> _empleadosInactivos = [];
  
  bool _isLoadingActivos = true;
  bool _isLoadingInactivos = true;
  bool _isLoadingMoreActivos = false;
  bool _isLoadingMoreInactivos = false;
  
  int _currentPageActivos = 1;
  int _totalPagesActivos = 1;
  int _currentPageInactivos = 1;
  int _totalPagesInactivos = 1;
  
  final int _limit = 20;
  
  late ScrollController _scrollControllerActivos;
  late ScrollController _scrollControllerInactivos;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _tabController = TabController(length: 2, vsync: this);
    _scrollControllerActivos = ScrollController();
    _scrollControllerInactivos = ScrollController();
    
    _scrollControllerActivos.addListener(() => _onScrollActivos());
    _scrollControllerInactivos.addListener(() => _onScrollInactivos());
    
    _loadEmpleadosActivos();
    _loadEmpleadosInactivos();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollControllerActivos.dispose();
    _scrollControllerInactivos.dispose();
    super.dispose();
  }

  void _onScrollActivos() {
    if (_scrollControllerActivos.position.pixels >=
        _scrollControllerActivos.position.maxScrollExtent - 100) {
      if (_currentPageActivos < _totalPagesActivos && !_isLoadingMoreActivos) {
        _loadMoreEmpleadosActivos();
      }
    }
  }

  void _onScrollInactivos() {
    if (_scrollControllerInactivos.position.pixels >=
        _scrollControllerInactivos.position.maxScrollExtent - 100) {
      if (_currentPageInactivos < _totalPagesInactivos && !_isLoadingMoreInactivos) {
        _loadMoreEmpleadosInactivos();
      }
    }
  }

  Future<void> _loadEmpleadosActivos() async {
    setState(() {
      _isLoadingActivos = true;
      _currentPageActivos = 1;
    });

    try {
      final response = await _apiService.getEmpleados(
        widget.token,
        page: _currentPageActivos,
        limit: _limit,
      );

      if (mounted && response['success']) {
        setState(() {
          final dataResponse = response['data'];
          List<dynamic> empleados = [];
          
          if (dataResponse is Map && dataResponse.containsKey('data')) {
            empleados = dataResponse['data'] ?? [];
            _totalPagesActivos = dataResponse['pagination']?['totalPages'] ?? 1;
          } else if (dataResponse is List) {
            empleados = dataResponse;
            _totalPagesActivos = response['totalPages'] ?? 1;
          } else {
            empleados = [];
            _totalPagesActivos = 1;
          }
          
          _empleadosActivos = empleados;
          _isLoadingActivos = false;
          
          if (_currentPageActivos < _totalPagesActivos) {
            _currentPageActivos++;
          }
        });
      } else {
        setState(() {
          _isLoadingActivos = false;
        });
        _showSnack(response['message'] ?? 'Error al cargar empleados', isError: true);
      }
    } catch (e) {
      setState(() {
        _isLoadingActivos = false;
      });
      _showSnack('Error de conexión: $e', isError: true);
    }
  }

  Future<void> _loadMoreEmpleadosActivos() async {
    setState(() {
      _isLoadingMoreActivos = true;
    });

    try {
      final response = await _apiService.getEmpleados(
        widget.token,
        page: _currentPageActivos,
        limit: _limit,
      );

      if (mounted && response['success']) {
        setState(() {
          final dataResponse = response['data'];
          List<dynamic> nuevosEmpleados = [];
          
          if (dataResponse is Map && dataResponse.containsKey('data')) {
            nuevosEmpleados = dataResponse['data'] ?? [];
            _totalPagesActivos = dataResponse['pagination']?['totalPages'] ?? 1;
          } else if (dataResponse is List) {
            nuevosEmpleados = dataResponse;
            _totalPagesActivos = response['totalPages'] ?? 1;
          }
          
          _empleadosActivos.addAll(nuevosEmpleados);
          _isLoadingMoreActivos = false;
          
          if (_currentPageActivos < _totalPagesActivos) {
            _currentPageActivos++;
          }
        });
      } else {
        setState(() {
          _isLoadingMoreActivos = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingMoreActivos = false;
      });
    }
  }

  Future<void> _loadEmpleadosInactivos() async {
    setState(() {
      _isLoadingInactivos = true;
      _currentPageInactivos = 1;
    });

    try {
      final response = await _apiService.getEmpleadosInactivos(
        widget.token,
        page: _currentPageInactivos,
        limit: _limit,
      );

      if (mounted && response['success']) {
        setState(() {
          final dataResponse = response['data'];
          List<dynamic> empleados = [];
          
          if (dataResponse is Map && dataResponse.containsKey('data')) {
            empleados = dataResponse['data'] ?? [];
            _totalPagesInactivos = dataResponse['pagination']?['totalPages'] ?? 1;
          } else if (dataResponse is List) {
            empleados = dataResponse;
            _totalPagesInactivos = response['totalPages'] ?? 1;
          } else {
            empleados = [];
            _totalPagesInactivos = 1;
          }
          
          _empleadosInactivos = empleados;
          _isLoadingInactivos = false;
          
          if (_currentPageInactivos < _totalPagesInactivos) {
            _currentPageInactivos++;
          }
        });
      } else {
        setState(() {
          _isLoadingInactivos = false;
        });
        _showSnack(response['message'] ?? 'Error al cargar empleados inactivos', isError: true);
      }
    } catch (e) {
      setState(() {
        _isLoadingInactivos = false;
      });
      _showSnack('Error de conexión: $e', isError: true);
    }
  }

  Future<void> _loadMoreEmpleadosInactivos() async {
    setState(() {
      _isLoadingMoreInactivos = true;
    });

    try {
      final response = await _apiService.getEmpleadosInactivos(
        widget.token,
        page: _currentPageInactivos,
        limit: _limit,
      );

      if (mounted && response['success']) {
        setState(() {
          final dataResponse = response['data'];
          List<dynamic> nuevosEmpleados = [];
          
          if (dataResponse is Map && dataResponse.containsKey('data')) {
            nuevosEmpleados = dataResponse['data'] ?? [];
            _totalPagesInactivos = dataResponse['pagination']?['totalPages'] ?? 1;
          } else if (dataResponse is List) {
            nuevosEmpleados = dataResponse;
            _totalPagesInactivos = response['totalPages'] ?? 1;
          }
          
          _empleadosInactivos.addAll(nuevosEmpleados);
          _isLoadingMoreInactivos = false;
          
          if (_currentPageInactivos < _totalPagesInactivos) {
            _currentPageInactivos++;
          }
        });
      } else {
        setState(() {
          _isLoadingMoreInactivos = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingMoreInactivos = false;
      });
    }
  }

  Future<void> _inactivarEmpleado(Map<String, dynamic> empleado) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Inactivar Empleado', style: TextStyle(color: AppTheme.textPrimary)),
          content: Text(
            '¿Estás seguro de que deseas inactivar a ${empleado['nombre']}?',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppTheme.error),
              child: Text('Inactivar', style: TextStyle(color: AppTheme.error)),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      setState(() {
        _isLoadingActivos = true;
      });

      try {
        final response = await _apiService.inactivarEmpleado(widget.token, empleado['id_usuario']);

        if (mounted && response['success']) {
          _showSnack(response['message']);
          await _loadEmpleadosActivos();
          await _loadEmpleadosInactivos();
        } else {
          _showSnack(response['message'] ?? 'Error al inactivar empleado', isError: true);
          setState(() {
            _isLoadingActivos = false;
          });
        }
      } catch (e) {
        _showSnack('Error de conexión: $e', isError: true);
        setState(() {
          _isLoadingActivos = false;
        });
      }
    }
  }

  Future<void> _reactivarEmpleado(Map<String, dynamic> empleado) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Reactivar Empleado', style: TextStyle(color: AppTheme.textPrimary)),
          content: Text(
            '¿Estás seguro de que deseas reactivar a ${empleado['nombre']}?',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Reactivar', style: TextStyle(color: AppTheme.green)),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      setState(() {
        _isLoadingInactivos = true;
      });

      try {
        final response = await _apiService.reactivarEmpleado(widget.token, empleado['id_usuario']);

        if (mounted && response['success']) {
          _showSnack(response['message']);
          await _loadEmpleadosActivos();
          await _loadEmpleadosInactivos();
        } else {
          _showSnack(response['message'] ?? 'Error al reactivar empleado', isError: true);
          setState(() {
            _isLoadingInactivos = false;
          });
        }
      } catch (e) {
        _showSnack('Error de conexión: $e', isError: true);
        setState(() {
          _isLoadingInactivos = false;
        });
      }
    }
  }

  void _showEmpleadoDetalle(Map<String, dynamic> empleado) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Center(
          child: CircularProgressIndicator(color: AppTheme.green),
        );
      },
    );

    try {
      final response = await _apiService.getEmpleadoDetalle(widget.token, empleado['id_usuario']);

      Navigator.pop(context);

      if (mounted && response['success']) {
        final detalle = response['empleado'];
        
        if (detalle != null) {
          _showDetalleDialog(detalle);
        } else {
          _showSnack('No se pudo obtener el detalle del empleado', isError: true);
        }
      } else {
        _showSnack(response['message'] ?? 'Error al obtener detalle', isError: true);
      }
    } catch (e) {
      Navigator.pop(context);
      _showSnack('Error de conexión: ${e.toString()}', isError: true);
    }
  }

  void _showDetalleDialog(Map<String, dynamic> empleado) {
    final bool tieneFoto = empleado['foto_perfil_url'] != null && 
                           empleado['foto_perfil_url'].toString().isNotEmpty;
    
    final String nombre = empleado['nombre']?.toString() ?? 'No disponible';
    final String email = empleado['email']?.toString() ?? 'No disponible';
    final String rol = empleado['rol']?.toString() ?? 'empleado';
    final String nombreNegocio = empleado['nombre_negocio']?.toString() ?? 'No disponible';
    final String totalTransferencias = empleado['total_transferencias']?.toString() ?? '0';
    final String totalMonto = empleado['total_monto_transferencias']?.toString() ?? '0';
    final String ultimaTransferencia = _formatFecha(empleado['ultima_transferencia_fecha']);
    final String fechaRegistro = _formatFecha(empleado['fecha_registro']);
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.person, color: AppTheme.green),
              const SizedBox(width: 8),
              const Text('Detalle del Empleado', style: TextStyle(color: AppTheme.textPrimary)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: _buildProfileImage(
                    empleado['foto_perfil_url'] ?? '',
                    tieneFoto,
                    nombre,
                    80,
                  ),
                ),
                const SizedBox(height: 16),
                _buildDetalleRow('Nombre:', nombre),
                const SizedBox(height: 8),
                _buildDetalleRow('Email:', email),
                const SizedBox(height: 8),
                _buildDetalleRow('Rol:', rol),
                const SizedBox(height: 8),
                _buildDetalleRow('Negocio:', nombreNegocio),
                const SizedBox(height: 8),
                _buildDetalleRow('Total Transferencias:', totalTransferencias),
                const SizedBox(height: 8),
                _buildDetalleRow('Total Monto:', '\$${double.tryParse(totalMonto)?.toStringAsFixed(2) ?? '0.00'}'),
                const SizedBox(height: 8),
                _buildDetalleRow('Última Transferencia:', ultimaTransferencia),
                const SizedBox(height: 8),
                _buildDetalleRow('Fecha Registro:', fechaRegistro),
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

  Widget _buildDetalleRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.green),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value, style: const TextStyle(color: AppTheme.textPrimary)),
        ),
      ],
    );
  }

  String _formatFecha(String? fechaISO) {
    if (fechaISO == null) return 'No disponible';
    try {
      final fecha = DateTime.parse(fechaISO);
      return '${fecha.day}/${fecha.month}/${fecha.year}';
    } catch (e) {
      return 'No disponible';
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

  Widget _buildEmployeeCard(Map<String, dynamic> empleado, {bool isActive = true}) {
    final bool tieneFoto = empleado['foto_perfil_url'] != null && empleado['foto_perfil_url'].isNotEmpty;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppTheme.border, width: 0.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _buildProfileImage(
          empleado['foto_perfil_url'] ?? '',
          tieneFoto,
          empleado['nombre'],
          50,
        ),
        title: Text(
          empleado['nombre'] ?? 'Sin nombre',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              empleado['email'] ?? 'Sin email',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              'Registrado: ${_formatFecha(empleado['fecha_registro'])}',
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppTheme.bgDark,
                borderRadius: BorderRadius.circular(8),
              ),
              child: IconButton(
                icon: Icon(Icons.visibility, color: AppTheme.green),
                onPressed: () => _showEmpleadoDetalle(empleado),
                tooltip: 'Ver detalles',
              ),
            ),
            const SizedBox(width: 4),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.bgDark,
                borderRadius: BorderRadius.circular(8),
              ),
              child: isActive
                  ? IconButton(
                      icon: Icon(Icons.block, color: AppTheme.error),
                      onPressed: () => _inactivarEmpleado(empleado),
                      tooltip: 'Inactivar',
                    )
                  : IconButton(
                      icon: Icon(Icons.replay, color: AppTheme.green),
                      onPressed: () => _reactivarEmpleado(empleado),
                      tooltip: 'Reactivar',
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileImage(String fotoUrl, bool tieneFoto, String? nombre, double size) {
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
            child: CircularProgressIndicator(color: AppTheme.green),
          ),
          errorWidget: (context, url, error) => CircleAvatar(
            radius: size / 2,
            backgroundColor: AppTheme.surfaceLight,
            child: Text(
              nombre?.substring(0, 1).toUpperCase() ?? 'U',
              style: TextStyle(
                fontSize: size / 2,
                fontWeight: FontWeight.bold,
                color: AppTheme.green,
              ),
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
          style: TextStyle(
            fontSize: size / 2,
            fontWeight: FontWeight.bold,
            color: AppTheme.green,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: const Text('Gestionar Empleados', style: TextStyle(color: AppTheme.textPrimary)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.backgroundGradient,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.green,
          labelColor: AppTheme.green,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: const [
            Tab(text: 'Activos', icon: Icon(Icons.people)),
            Tab(text: 'Inactivos', icon: Icon(Icons.people_outline)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab de empleados activos
          _isLoadingActivos
              ? Center(child: CircularProgressIndicator(color: AppTheme.green))
              : _empleadosActivos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people, size: 64, color: AppTheme.textDisabled),
                          const SizedBox(height: 16),
                          Text(
                            'No hay empleados activos',
                            style: const TextStyle(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollControllerActivos,
                      padding: const EdgeInsets.all(16),
                      itemCount: _empleadosActivos.length + (_isLoadingMoreActivos ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _empleadosActivos.length) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator(color: AppTheme.green)),
                          );
                        }
                        return _buildEmployeeCard(_empleadosActivos[index], isActive: true);
                      },
                    ),
          
          // Tab de empleados inactivos
          _isLoadingInactivos
              ? Center(child: CircularProgressIndicator(color: AppTheme.green))
              : _empleadosInactivos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline, size: 64, color: AppTheme.textDisabled),
                          const SizedBox(height: 16),
                          Text(
                            'No hay empleados inactivos',
                            style: const TextStyle(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollControllerInactivos,
                      padding: const EdgeInsets.all(16),
                      itemCount: _empleadosInactivos.length + (_isLoadingMoreInactivos ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _empleadosInactivos.length) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator(color: AppTheme.green)),
                          );
                        }
                        return _buildEmployeeCard(_empleadosInactivos[index], isActive: false);
                      },
                    ),
        ],
      ),
    );
  }
}