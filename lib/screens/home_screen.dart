// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:async';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/connectivity_service.dart';
import '../offline/offline_manager.dart';
import '../offline/sync_manager.dart';
import 'settings_screen.dart';
import 'add_transferencia_screen.dart';
import 'pending_transfers_screen.dart';
import 'edit_transferencia_screen.dart';

class HomeScreen extends StatefulWidget {
  final String token;

  const HomeScreen({Key? key, required this.token}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late ApiService _apiService;
  Map<String, dynamic> _userData = {};
  Map<String, dynamic> _totalData = {};
  List<dynamic> _transferencias = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String _errorMessage = '';
  String _filtroActual = 'hoy';
  DateTime _fechaSeleccionada = DateTime.now();

  // Variables offline
  late DatabaseService _dbService;
  late ConnectivityService _connectivityService;
  late OfflineManager _offlineManager;
  late SyncManager _syncManager;
  bool _isOnline = true;
  StreamSubscription? _connectionSubscription;
  
  final ValueNotifier<int> _pendingCountNotifier = ValueNotifier<int>(0);
  Timer? _pendingTimer;
  
  // Variables para paginación
  int _currentPage = 1;
  int _totalPages = 1;
  bool _hasMorePages = true;
  final int _limit = 10;
  
  late ScrollController _scrollController;
  bool _showScrollToTopButton = false;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _dbService = DatabaseService();
    _connectivityService = ConnectivityService();
    _offlineManager = OfflineManager();
    _syncManager = SyncManager();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    
    _connectivityService.initialize();
    _connectionSubscription = _connectivityService.onConnectionChange.listen((isOnline) async {
      setState(() {
        _isOnline = isOnline;
      });
      if (isOnline) {
        final result = await _syncManager.syncPendingTransfers(widget.token);
        if (result['sincronizadas'] > 0) {
          _showSnack('✅ ${result['sincronizadas']} transferencias sincronizadas');
          await _updatePendingCount();
          _loadAllData();
        }
      }
    });
    
    _loadAllData();
    _startPendingCountUpdater();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _connectionSubscription?.cancel();
    _pendingTimer?.cancel();
    _pendingCountNotifier.dispose();
    super.dispose();
  }

  Future<void> _updatePendingCount() async {
    final pendientes = await _dbService.getTransferenciasPendientes();
    _pendingCountNotifier.value = pendientes.length;
  }

  void _startPendingCountUpdater() {
    _updatePendingCount();
    _pendingTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
      if (mounted) {
        await _updatePendingCount();
      }
    });
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  void _onScroll() {
    if (_scrollController.position.pixels > 250) {
      if (!_showScrollToTopButton) {
        setState(() {
          _showScrollToTopButton = true;
        });
      }
    } else {
      if (_showScrollToTopButton) {
        setState(() {
          _showScrollToTopButton = false;
        });
      }
    }
    
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 100) {
      if (_hasMorePages && !_isLoadingMore && !_isLoading) {
        _loadMoreTransferencias();
      }
    }
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _currentPage = 1;
      _transferencias = [];
      _hasMorePages = true;
    });

    final hasInternet = await _connectivityService.hasInternet();
    
    if (hasInternet) {
      try {
        await Future.wait([
          _loadUserData(),
          _loadTotalData(),
          _loadTransferencias(reset: true),
        ]);
        
        await _offlineManager.saveDataToCache(
          userData: _userData,
          totalData: _totalData,
          transferencias: _transferencias,
          periodo: '${_filtroActual}-${_getPeriodoTexto()}',
        );
      } catch (e) {
        await _loadDataFromCache();
      }
    } else {
      await _loadDataFromCache();
      
      if (_transferencias.isEmpty && _userData.isEmpty) {
        setState(() {
          _errorMessage = 'Sin conexión a internet. Conéctate para ver tus datos.';
        });
      } else {
        _showSnack('Modo offline - Mostrando datos guardados');
      }
    }

    setState(() {
      _isLoading = false;
    });
    
    await _updatePendingCount();
  }

  Future<void> _loadDataFromCache() async {
    final cacheData = await _offlineManager.loadDataFromCache();
    
    if (cacheData['usuario'] != null) {
      setState(() {
        _userData = cacheData['usuario'];
      });
    }
    
    if (cacheData['transferencias'] != null) {
      setState(() {
        _transferencias = cacheData['transferencias'];
      });
    }
    
    final totalCache = await _dbService.getTotalCache('${_filtroActual}-${_getPeriodoTexto()}');
    if (totalCache != null) {
      setState(() {
        _totalData = {
          'total': totalCache['total'],
          'moneda': totalCache['moneda'],
        };
      });
    }
  }

  Future<void> _loadUserData() async {
    try {
      final response = await _apiService.getCurrentUser(widget.token);
      if (mounted && response['success']) {
        final data = response['data'];
        if (data is Map) {
          Map<String, dynamic> convertedData = {};
          data.forEach((key, value) {
            convertedData[key.toString()] = value;
          });
          setState(() {
            _userData = convertedData;
          });
        }
      }
    } catch (e) {
      print('Error loading user data: $e');
    }
  }

  Future<void> _loadTotalData() async {
    try {
      Map<String, dynamic> response;
      
      switch (_filtroActual) {
        case 'hoy':
          response = await _apiService.getTotalHoy(widget.token);
          break;
        case 'dia':
          String fecha = _fechaSeleccionada.toIso8601String().split('T')[0];
          response = await _apiService.getTotalPorDia(widget.token, fecha);
          break;
        case 'mes':
          response = await _apiService.getTotalMes(
            widget.token, 
            _fechaSeleccionada.year, 
            _fechaSeleccionada.month
          );
          break;
        case 'anio':
          response = await _apiService.getTotalAnio(
            widget.token, 
            _fechaSeleccionada.year
          );
          break;
        default:
          response = await _apiService.getTotalHoy(widget.token);
      }
      
      if (mounted && response['success']) {
        final data = response['data'];
        
        double total = 0;
        String moneda = 'USD';
        
        if (data is Map) {
          total = (data['total'] ?? 0).toDouble();
          moneda = data['moneda'] ?? 'USD';
        } else if (data is num) {
          total = data.toDouble();
        }
        
        setState(() {
          _totalData = {
            'total': total,
            'moneda': moneda,
          };
        });
      }
    } catch (e) {
      setState(() {
        _totalData = {
          'total': 0,
          'moneda': 'USD',
        };
      });
    }
  }

  Future<void> _loadTransferencias({bool reset = false}) async {
    if (reset) {
      _currentPage = 1;
      _hasMorePages = true;
      _transferencias = [];
    }
    
    if (!_hasMorePages && !reset) return;
    
    setState(() {
      if (_currentPage == 1) {
        _isLoading = true;
      } else {
        _isLoadingMore = true;
      }
    });

    try {
      final response = await _apiService.getTransferencias(
        widget.token,
        page: _currentPage,
        limit: _limit,
      );
      
      if (mounted && response['success']) {
        setState(() {
          final dataResponse = response['data'];
          List<dynamic> nuevasTransferencias = [];
          
          if (dataResponse is List) {
            nuevasTransferencias = dataResponse;
            _totalPages = response['totalPages'] ?? 1;
          } else if (dataResponse is Map && dataResponse.containsKey('data')) {
            nuevasTransferencias = dataResponse['data'] ?? [];
            _totalPages = dataResponse['pagination']?['totalPages'] ?? 1;
          } else {
            nuevasTransferencias = [];
            _totalPages = 1;
          }
          
          if (reset) {
            _transferencias = nuevasTransferencias;
          } else {
            final idsExistentes = _transferencias.map((t) => t['id_transferencia']).toSet();
            final nuevosUnicos = nuevasTransferencias.where((t) => !idsExistentes.contains(t['id_transferencia'])).toList();
            _transferencias.addAll(nuevosUnicos);
          }
          
          if (_currentPage < _totalPages) {
            _currentPage++;
            _hasMorePages = true;
          } else {
            _hasMorePages = false;
          }
          
          _isLoading = false;
          _isLoadingMore = false;
        });
      } else {
        setState(() {
          if (_currentPage == 1) {
            _errorMessage = response['message'] ?? 'Error al cargar transferencias';
          }
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error de conexión: ${e.toString()}';
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _loadMoreTransferencias() async {
    if (!_hasMorePages || _isLoadingMore || _isLoading) return;
    await _loadTransferencias(reset: false);
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    final GoogleSignIn googleSignIn = GoogleSignIn();
    await googleSignIn.signOut();
    if (mounted) {
      Navigator.pushReplacementNamed(context, "/login");
    }
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Filtrar por', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              SizedBox(height: 20),
              ListTile(
                leading: Icon(Icons.today),
                title: Text('Hoy'),
                trailing: _filtroActual == 'hoy' ? Icon(Icons.check, color: Colors.blue) : null,
                onTap: () {
                  setState(() {
                    _filtroActual = 'hoy';
                    _loadTotalData();
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.calendar_today),
                title: Text('Día específico'),
                trailing: _filtroActual == 'dia' ? Icon(Icons.check, color: Colors.blue) : null,
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _fechaSeleccionada,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (date != null) {
                    setState(() {
                      _filtroActual = 'dia';
                      _fechaSeleccionada = date;
                      _loadTotalData();
                    });
                  }
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.calendar_month),
                title: Text('Mes'),
                trailing: _filtroActual == 'mes' ? Icon(Icons.check, color: Colors.blue) : null,
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _fechaSeleccionada,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (date != null) {
                    setState(() {
                      _filtroActual = 'mes';
                      _fechaSeleccionada = date;
                      _loadTotalData();
                    });
                  }
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.date_range),
                title: Text('Año'),
                trailing: _filtroActual == 'anio' ? Icon(Icons.check, color: Colors.blue) : null,
                onTap: () async {
                  final year = await showDialog<int>(
                    context: context,
                    builder: (context) {
                      int selectedYear = DateTime.now().year;
                      return AlertDialog(
                        title: Text('Seleccionar año'),
                        content: DropdownButton<int>(
                          value: selectedYear,
                          isExpanded: true,
                          items: List.generate(10, (i) {
                            int year = DateTime.now().year - i;
                            return DropdownMenuItem(
                              value: year,
                              child: Text(year.toString()),
                            );
                          }),
                          onChanged: (value) {
                            if (value != null) {
                              selectedYear = value;
                              Navigator.pop(context, selectedYear);
                            }
                          },
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text('Cancelar'),
                          ),
                        ],
                      );
                    },
                  );
                  if (year != null) {
                    setState(() {
                      _filtroActual = 'anio';
                      _fechaSeleccionada = DateTime(year);
                      _loadTotalData();
                    });
                  }
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  String _getPeriodoTexto() {
    switch (_filtroActual) {
      case 'hoy': return 'Hoy';
      case 'dia': return '${_fechaSeleccionada.day}/${_fechaSeleccionada.month}/${_fechaSeleccionada.year}';
      case 'mes': return '${_fechaSeleccionada.month}/${_fechaSeleccionada.year}';
      case 'anio': return '${_fechaSeleccionada.year}';
      default: return 'Hoy';
    }
  }

  String _formatMonto(dynamic monto) {
    double valor = 0;
    if (monto is int) valor = monto.toDouble();
    else if (monto is double) valor = monto;
    else if (monto is String) valor = double.tryParse(monto) ?? 0;
    return '\$${valor.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
  }

  String _formatFecha(String? fechaISO) {
    if (fechaISO == null) return 'Fecha no disponible';
    try {
      final fecha = DateTime.parse(fechaISO);
      return '${fecha.day}/${fecha.month}/${fecha.year}';
    } catch (e) {
      return 'Fecha no disponible';
    }
  }
  Future<String> _getValidToken() async {
  if (widget.token.isNotEmpty) {
    return widget.token;
  }
  // Si el token del widget está vacío, obtenerlo de SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  final savedToken = prefs.getString('token') ?? '';
  print('Token recuperado de SharedPreferences: ${savedToken.length}');
  return savedToken;
}

 void _showTransferenciaDetalle(Map<String, dynamic> transferencia) async {
  // Mostrar loading
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return Center(child: CircularProgressIndicator());
    },
  );
  
  try {
    final token = await _getValidToken();
    if (token.isEmpty) {
      Navigator.pop(context);
      _showSnack('Error: Sesión expirada', isError: true);
      return;
    }
    
    // ✅ Obtener datos actualizados incluyendo disponible_para_editar
    final response = await _apiService.getTransferenciaById(
      token,
      transferencia['id_transferencia'],
    );
    
    // Cerrar loading
    Navigator.pop(context);
    
    if (response['success']) {
      final transferenciaActualizada = response['data'];
      final esDueno = _userData['es_dueno'] ?? false;
      final puedeEditar = transferenciaActualizada['disponible_para_editar'] ?? false;
      final puedeEliminar = esDueno;
      
      print('=== TRANSFERENCIA ACTUALIZADA ===');
      print('esDueno: $esDueno');
      print('disponible_para_editar: $puedeEditar');
      
      _mostrarDialogoDetalle(transferenciaActualizada, esDueno, puedeEditar, puedeEliminar);
    } else {
      _showSnack(response['message'] ?? 'Error al cargar detalles', isError: true);
    }
  } catch (e) {
    Navigator.pop(context);
    print('Error en _showTransferenciaDetalle: $e');
    _showSnack('Error de conexión: ${e.toString()}', isError: true);
  }
}

void _mostrarDialogoDetalle(Map<String, dynamic> transferencia, bool esDueno, bool puedeEditar, bool puedeEliminar) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text('Detalle de Transferencia'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetalleRow('Banco:', transferencia['banco'] ?? 'No especificado'),
              SizedBox(height: 8),
              _buildDetalleRow('Monto:', _formatMonto(transferencia['monto'])),
              SizedBox(height: 8),
              _buildDetalleRow('Fecha:', _formatFecha(transferencia['fecha_transferencia'])),
              SizedBox(height: 8),
              _buildDetalleRow('Registrado por:', transferencia['usuario_nombre'] ?? 'Usuario desconocido'),
              SizedBox(height: 8),
              _buildDetalleRow('Estado:', transferencia['estado'] ?? 'No especificado'),
              if (transferencia['observaciones'] != null && 
                  transferencia['observaciones'].toString().isNotEmpty) ...[
                SizedBox(height: 8),
                _buildDetalleRow('Observaciones:', transferencia['observaciones']),
              ],
              if (transferencia['url_comprobante'] != null && 
                  transferencia['url_comprobante'].toString().isNotEmpty) ...[
                SizedBox(height: 12),
                Text('Comprobante:', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                InkWell(
                  onTap: () => _showComprobanteImagen(transferencia['url_comprobante']),
                  child: Container(
                    height: 150,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      image: DecorationImage(
                        image: CachedNetworkImageProvider(transferencia['url_comprobante']),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ],
              // ✅ Mensaje si no está disponible para editar
              if (!esDueno && !puedeEditar)
                Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.timer_off, size: 16, color: Colors.red),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Ya no puedes editar esta transferencia. El tiempo para editarla ha expirado.',
                            style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          // ✅ Botón Editar (solo empleados y si disponible_para_editar es true)
         if (esDueno || (!esDueno && puedeEditar))
            TextButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                final token = await _getValidToken();
                if (token.isEmpty) return;
                
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditTransferenciaScreen(
                      token: token,
                      transferencia: transferencia,
                      puedeEditar: true,
                    ),
                  ),
                );
                if (result == true) {
                  _loadAllData();
                }
              },
              icon: Icon(Icons.edit, color: Colors.blue),
              label: Text('Editar', style: TextStyle(color: Colors.blue)),
            ),
          // ✅ Botón Eliminar (solo dueños)
          if (puedeEliminar)
            TextButton.icon(
              onPressed: () async {
                final token = await _getValidToken();
                if (token.isEmpty) return;
                _confirmarEliminar(transferencia, token);
              },
              icon: Icon(Icons.delete, color: Colors.red),
              label: Text('Eliminar', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cerrar'),
          ),
        ],
      );
    },
  );
}

  Future<void> _confirmarEliminar(Map<String, dynamic> transferencia, String token) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text('Eliminar Transferencia'),
        content: Text('¿Estás seguro de que deseas eliminar esta transferencia? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Eliminar'),
          ),
        ],
      );
    },
  );

  if (confirm == true) {
    setState(() {
      _isLoading = true;
    });
    
    try {
      print('=== ELIMINANDO TRANSFERENCIA ===');
      print('ID: ${transferencia['id_transferencia']}');
      print('Token length: ${token.length}');
      
      final response = await _apiService.eliminarTransferencia(
        token,
        transferencia['id_transferencia'],
      );
      
      print('Respuesta eliminar: $response');
      
      if (response['success']) {
        _showSnack(response['message']);
        _loadAllData();
      } else {
        _showSnack(response['message'] ?? 'Error al eliminar', isError: true);
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error en eliminar: $e');
      _showSnack('Error de conexión: ${e.toString()}', isError: true);
      setState(() {
        _isLoading = false;
      });
    }
  }
}

  Widget _buildDetalleRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700])),
        SizedBox(width: 8),
        Expanded(child: Text(value)),
      ],
    );
  }

  void _showComprobanteImagen(String url) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Container(
            width: double.maxFinite,
            height: 500,
            child: Column(
              children: [
                AppBar(
                  title: Text('Comprobante'),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  automaticallyImplyLeading: false,
                  actions: [
                    IconButton(icon: Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                Expanded(
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => Center(child: CircularProgressIndicator()),
                    errorWidget: (context, url, error) => Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 48, color: Colors.red),
                          SizedBox(height: 16),
                          Text('No se pudo cargar la imagen'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileImage(String fotoUrl, bool tieneFoto, String? nombre) {
    final double size = 50;
    
    if (tieneFoto && fotoUrl.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: fotoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(width: size, height: size, child: CircularProgressIndicator()),
          errorWidget: (context, url, error) => CircleAvatar(
            radius: size / 2,
            backgroundColor: Colors.blue.shade100,
            child: Text(nombre?.substring(0, 1).toUpperCase() ?? 'U', style: TextStyle(fontSize: size / 2, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
          ),
        ),
      );
    } else {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: Colors.blue.shade100,
        child: Text(nombre?.substring(0, 1).toUpperCase() ?? 'U', style: TextStyle(fontSize: size / 2, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final String fotoPerfilUrl = _userData['foto_perfil_url'] ?? _userData['fotoPerfilUrl'] ?? '';
    final bool tieneFoto = _userData['tiene_foto_perfil'] ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text("PillaPago"),
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
        automaticallyImplyLeading: false,
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: _pendingCountNotifier,
            builder: (context, pendingCount, child) {
              return Stack(
                children: [
                  IconButton(
                    icon: Icon(Icons.pending_actions),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PendingTransfersScreen(token: widget.token),
                        ),
                      );
                      await _updatePendingCount();
                      _loadAllData();
                    },
                  ),
                  if (pendingCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          '$pendingCount',
                          style: TextStyle(color: Colors.white, fontSize: 10),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(token: widget.token),
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadAllData,
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty && _transferencias.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 64, color: Colors.red),
                            SizedBox(height: 16),
                            Text(_errorMessage),
                            SizedBox(height: 16),
                            ElevatedButton(onPressed: _loadAllData, child: Text('Reintentar')),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        controller: _scrollController,
                        physics: AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _buildProfileImage(fotoPerfilUrl, tieneFoto, _userData['nombre']),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Hola, ${_userData['nombre']?.split(' ')[0] ?? 'Usuario'}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                      Text(_userData['nombre_negocio'] ?? 'Sin negocio', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 24),
                            Card(
                              elevation: 4,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: InkWell(
                                onTap: _showFilterDialog,
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('Total', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                                          Container(
                                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(20)),
                                            child: Row(
                                              children: [
                                                Text(_getPeriodoTexto(), style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500)),
                                                SizedBox(width: 4),
                                                Icon(Icons.arrow_drop_down, color: Colors.blue),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 16),
                                      Text(_formatMonto(_totalData['total'] ?? 0), style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                                      SizedBox(height: 8),
                                      Text(_totalData['moneda'] ?? 'USD', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => AddTransferenciaScreen(token: widget.token)),
                                  );
                                  if (result == true) {
                                    await _updatePendingCount();
                                    _loadAllData();
                                  }
                                },
                                icon: Icon(Icons.add_circle_outline),
                                label: Text('Añadir Transferencia', style: TextStyle(fontSize: 16)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Historial', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                if (_transferencias.isNotEmpty)
                                  Text('${_transferencias.length} registros', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                              ],
                            ),
                            SizedBox(height: 12),
                            _transferencias.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(40),
                                      child: Column(
                                        children: [
                                          Icon(Icons.history, size: 64, color: Colors.grey[400]),
                                          SizedBox(height: 16),
                                          Text('No hay transferencias registradas', style: TextStyle(color: Colors.grey[600])),
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    shrinkWrap: true,
                                    physics: NeverScrollableScrollPhysics(),
                                    itemCount: _transferencias.length + (_isLoadingMore ? 1 : 0),
                                    itemBuilder: (context, index) {
                                      if (index == _transferencias.length && _isLoadingMore) {
                                        return Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                                      }
                                      final transferencia = _transferencias[index];
                                      return Card(
                                        margin: EdgeInsets.only(bottom: 8),
                                        elevation: 2,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        child: InkWell(
                                          onTap: () => _showTransferenciaDetalle(transferencia),
                                          borderRadius: BorderRadius.circular(12),
                                          child: Padding(
                                            padding: EdgeInsets.all(12),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Row(
                                                    children: [
                                                      CircleAvatar(
                                                        backgroundColor: Colors.blue.shade100,
                                                        radius: 20,
                                                        child: Icon(Icons.account_balance, color: Colors.blue, size: 20),
                                                      ),
                                                      SizedBox(width: 12),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text(transferencia['banco'] ?? 'Banco no especificado', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                                            Row(
                                                              children: [
                                                                Icon(Icons.person, size: 12, color: Colors.grey[600]),
                                                                SizedBox(width: 4),
                                                                Expanded(
                                                                  child: Text(
                                                                    transferencia['usuario_nombre'] ?? transferencia['nombre_usuario'] ?? 'Usuario desconocido',
                                                                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                                                    maxLines: 1,
                                                                    overflow: TextOverflow.ellipsis,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                            if (transferencia['observaciones'] != null && transferencia['observaciones'].toString().isNotEmpty)
                                                              Text(transferencia['observaciones'], style: TextStyle(fontSize: 12, color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.end,
                                                  children: [
                                                    Text(_formatMonto(transferencia['monto']), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16)),
                                                    Text(_formatFecha(transferencia['fecha_transferencia']), style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ],
                        ),
                      ),
          ),
          if (_showScrollToTopButton)
            Positioned(
              bottom: 20,
              right: 20,
              child: FloatingActionButton(
                mini: true,
                onPressed: _scrollToTop,
                backgroundColor: Colors.blue,
                child: Icon(Icons.arrow_upward, color: Colors.white),
                elevation: 4,
              ),
            ),
        ],
      ),
    );
  }
}