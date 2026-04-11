// lib/screens/manage_employees_screen.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';

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

 // En manage_employees_screen.dart, corrige _loadEmpleadosActivos

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

    print('Respuesta empleados activos: $response');

    if (mounted && response['success']) {
      setState(() {
        // ✅ CORREGIDO: Extraer la lista de datos correctamente
        final dataResponse = response['data'];
        List<dynamic> empleados = [];
        
        // Verificar la estructura de la respuesta
        if (dataResponse is Map && dataResponse.containsKey('data')) {
          // Formato: { data: [], pagination: {} }
          empleados = dataResponse['data'] ?? [];
          _totalPagesActivos = dataResponse['pagination']?['totalPages'] ?? 1;
        } else if (dataResponse is List) {
          // Formato directo: []
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
        
        print('Empleados activos cargados: ${_empleadosActivos.length}');
        print('Total páginas: $_totalPagesActivos');
      });
    } else {
      setState(() {
        _isLoadingActivos = false;
      });
      _showSnack(response['message'] ?? 'Error al cargar empleados', isError: true);
    }
  } catch (e) {
    print('Error cargando empleados activos: $e');
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
        // ✅ CORREGIDO: Extraer la lista de datos correctamente
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
    print('Error cargando más empleados activos: $e');
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

    print('Respuesta empleados inactivos: $response');

    if (mounted && response['success']) {
      setState(() {
        // ✅ Ahora response['data'] ya es la lista directamente
        _empleadosInactivos = response['data'] ?? [];
        _totalPagesInactivos = response['totalPages'] ?? 1;
        _isLoadingInactivos = false;
        
        if (_currentPageInactivos < _totalPagesInactivos) {
          _currentPageInactivos++;
        }
        
        print('Empleados inactivos cargados: ${_empleadosInactivos.length}');
      });
    } else {
      setState(() {
        _isLoadingInactivos = false;
      });
      _showSnack(response['message'] ?? 'Error al cargar empleados inactivos', isError: true);
    }
  } catch (e) {
    print('Error cargando empleados inactivos: $e');
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
        // ✅ CORREGIDO: Extraer la lista de datos correctamente
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
    print('Error cargando más empleados inactivos: $e');
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
          title: Text('Inactivar Empleado'),
          content: Text('¿Estás seguro de que deseas inactivar a ${empleado['nombre']}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('Inactivar'),
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
          // Recargar ambas listas
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
          title: Text('Reactivar Empleado'),
          content: Text('¿Estás seguro de que deseas reactivar a ${empleado['nombre']}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.green),
              child: Text('Reactivar'),
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
          // Recargar ambas listas
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
  // Mostrar un loading mientras carga
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return Center(child: CircularProgressIndicator());
    },
  );

  try {
    final response = await _apiService.getEmpleadoDetalle(widget.token, empleado['id_usuario']);

    // Cerrar el dialog de loading
    Navigator.pop(context);

    print('Respuesta detalle empleado: $response');

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
    // Cerrar el dialog de loading si hay error
    Navigator.pop(context);
    print('Error en _showEmpleadoDetalle: $e');
    _showSnack('Error de conexión: ${e.toString()}', isError: true);
  }
}

 void _showDetalleDialog(Map<String, dynamic> empleado) {
  final bool tieneFoto = empleado['foto_perfil_url'] != null && 
                         empleado['foto_perfil_url'].toString().isNotEmpty;
  
  // Valores por defecto para evitar null
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
        title: Text('Detalle del Empleado'),
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
              SizedBox(height: 16),
              _buildDetalleRow('Nombre:', nombre),
              SizedBox(height: 8),
              _buildDetalleRow('Email:', email),
              SizedBox(height: 8),
              _buildDetalleRow('Rol:', rol),
              SizedBox(height: 8),
              _buildDetalleRow('Negocio:', nombreNegocio),
              SizedBox(height: 8),
              _buildDetalleRow('Total Transferencias:', totalTransferencias),
              SizedBox(height: 8),
              _buildDetalleRow('Total Monto:', '\$${double.tryParse(totalMonto)?.toStringAsFixed(2) ?? '0.00'}'),
              SizedBox(height: 8),
              _buildDetalleRow('Última Transferencia:', ultimaTransferencia),
              SizedBox(height: 8),
              _buildDetalleRow('Fecha Registro:', fechaRegistro),
            ],
          ),
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

Widget _buildDetalleRow(String label, String value) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700]),
      ),
      SizedBox(width: 8),
      Expanded(
        child: Text(value),
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
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Widget _buildEmployeeCard(Map<String, dynamic> empleado, {bool isActive = true}) {
    final bool tieneFoto = empleado['foto_perfil_url'] != null && empleado['foto_perfil_url'].isNotEmpty;
    
    return Card(
      margin: EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: _buildProfileImage(
          empleado['foto_perfil_url'] ?? '',
          tieneFoto,
          empleado['nombre'],
          50,
        ),
        title: Text(
          empleado['nombre'] ?? 'Sin nombre',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              empleado['email'] ?? 'Sin email',
              style: TextStyle(fontSize: 12),
            ),
            Text(
              'Registrado: ${_formatFecha(empleado['fecha_registro'])}',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.visibility, color: Colors.blue),
              onPressed: () => _showEmpleadoDetalle(empleado),
              tooltip: 'Ver detalles',
            ),
            if (isActive)
              IconButton(
                icon: Icon(Icons.block, color: Colors.red),
                onPressed: () => _inactivarEmpleado(empleado),
                tooltip: 'Inactivar',
              )
            else
              IconButton(
                icon: Icon(Icons.replay, color: Colors.green),
                onPressed: () => _reactivarEmpleado(empleado),
                tooltip: 'Reactivar',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Gestionar Empleados'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
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
              ? Center(child: CircularProgressIndicator())
              : _empleadosActivos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people, size: 64, color: Colors.grey[400]),
                          SizedBox(height: 16),
                          Text(
                            'No hay empleados activos',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollControllerActivos,
                      padding: EdgeInsets.all(16),
                      itemCount: _empleadosActivos.length + (_isLoadingMoreActivos ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _empleadosActivos.length) {
                          return Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return _buildEmployeeCard(_empleadosActivos[index], isActive: true);
                      },
                    ),
          
          // Tab de empleados inactivos
          _isLoadingInactivos
              ? Center(child: CircularProgressIndicator())
              : _empleadosInactivos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                          SizedBox(height: 16),
                          Text(
                            'No hay empleados inactivos',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollControllerInactivos,
                      padding: EdgeInsets.all(16),
                      itemCount: _empleadosInactivos.length + (_isLoadingMoreInactivos ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _empleadosInactivos.length) {
                          return Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
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