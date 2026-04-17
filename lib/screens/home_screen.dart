// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:async';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/connectivity_service.dart';
import '../services/notification_service.dart';
import '../offline/offline_manager.dart';
import '../offline/sync_manager.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';
import 'add_transferencia_screen.dart';
import 'pending_transfers_screen.dart';
import 'edit_transferencia_screen.dart';
import 'package:sqflite/sqflite.dart';
import 'package:fl_chart/fl_chart.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import '../services/notification_counter_service.dart';
import 'package:flutter/foundation.dart';

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
  bool _isOfflineMode = false;

  late DatabaseService _dbService;
  late ConnectivityService _connectivityService;
  late OfflineManager _offlineManager;
  late SyncManager _syncManager;
  bool _isOnline = true;
  StreamSubscription? _connectionSubscription;
  
  final ValueNotifier<int> _pendingCountNotifier = ValueNotifier<int>(0);
  Timer? _pendingTimer;
  
  int _currentPage = 1;
  int _totalPages = 1;
  bool _hasMorePages = true;
  final int _limit = 10;
  
  late ScrollController _scrollController;
  bool _showScrollToTopButton = false;

  List<Map<String, dynamic>> _estadisticas = [];
  bool _isLoadingEstadisticas = false;

  // Para el contador de notificaciones
  int _notificationCount = 0;

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
        if (isOnline) {
          _isOfflineMode = false;
        } else {
          _isOfflineMode = true;
        }
      });
      
      if (isOnline) {
        // Sincronizar transferencias pendientes
        final result = await _syncManager.syncPendingTransfers(widget.token);
        if (result['sincronizadas'] > 0) {
          _showSnack('✅ ${result['sincronizadas']} transferencias sincronizadas');
          await _updatePendingCount();
          _loadAllData();
        }
        
        // Sincronizar acciones pendientes de notificaciones
        await _syncNotifications();
        
        // Recargar contador de notificaciones
        await _loadNotificationCount();
      }
    });
    
    _loadAllData();
    _startPendingCountUpdater();
    _loadNotificationCount();
    
    // Escuchar cambios en el contador global
    NotificationCounterService.addListener(_onNotificationCountChanged);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _connectionSubscription?.cancel();
    _pendingTimer?.cancel();
    _pendingCountNotifier.dispose();
    NotificationCounterService.removeListener(_onNotificationCountChanged);
    super.dispose();
  }

  // Sincronizar acciones pendientes de notificaciones
  Future<void> _syncNotifications() async {
    try {
      final token = await _getValidToken();
      if (token.isNotEmpty) {
        final notificationService = NotificationService(token: token);
        final sincronizadas = await notificationService.sincronizarAccionesPendientes();
        if (sincronizadas > 0 && mounted) {
          _showSnack('✅ $sincronizadas notificaciones sincronizadas');
        }
      }
    } catch (e) {
      if (kDebugMode) print("Error sincronizando notificaciones: $e");
    }
  }

  // Listener para cambios en el contador
  void _onNotificationCountChanged(int count) {
    if (mounted) {
      setState(() {
        _notificationCount = count;
      });
    }
  }

  Future<void> _loadNotificationCount() async {
    final token = await _getValidToken();
    if (token.isNotEmpty) {
      try {
        await NotificationCounterService.loadUnreadCount(token);
        if (mounted) {
          setState(() {
            _notificationCount = NotificationCounterService.unreadCount;
            _isOfflineMode = false;
          });
        }
      } catch (e) {
        if (kDebugMode) print("📱 Modo offline - usando contador en caché");
        if (mounted) {
          setState(() {
            _notificationCount = NotificationCounterService.unreadCount;
            _isOfflineMode = true;
          });
        }
      }
    }
  }

  Future<void> _loadEstadisticas() async {
    setState(() {
      _isLoadingEstadisticas = true;
    });
    
    try {
      final token = await _getValidToken();
      if (token.isEmpty) {
        setState(() {
          _isLoadingEstadisticas = false;
        });
        return;
      }
      
      final response = await _apiService.getEstadisticasUltimos7Dias(token);
      
      if (mounted && response['success']) {
        setState(() {
          _estadisticas = List<Map<String, dynamic>>.from(response['data']['data']);
          _isLoadingEstadisticas = false;
        });
        await _guardarEstadisticasEnCache();
      } else {
        await _cargarEstadisticasDesdeCache();
        setState(() {
          _isLoadingEstadisticas = false;
        });
      }
    } catch (e) {
      await _cargarEstadisticasDesdeCache();
      setState(() {
        _isLoadingEstadisticas = false;
      });
    }
  }

  Future<void> _guardarEstadisticasEnCache() async {
    try {
      final db = await _dbService.database;
      await db.execute('''
        CREATE TABLE IF NOT EXISTS estadisticas_cache (
          id INTEGER PRIMARY KEY,
          data TEXT,
          fecha_actualizacion TEXT
        )
      ''');
      
      final dataStr = _estadisticas.map((e) => '${e['fecha']}|${e['total_transferencias']}').join(',');
      await db.insert(
        'estadisticas_cache',
        {
          'id': 1,
          'data': dataStr,
          'fecha_actualizacion': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      print('Error guardando estadísticas: $e');
    }
  }

  Future<void> _cargarEstadisticasDesdeCache() async {
    try {
      final db = await _dbService.database;
      final result = await db.query('estadisticas_cache', where: 'id = ?', whereArgs: [1]);
      if (result.isNotEmpty) {
        final dataStr = result.first['data'] as String;
        final items = dataStr.split(',');
        final List<Map<String, dynamic>> estadisticasCache = [];
        for (var item in items) {
          final parts = item.split('|');
          if (parts.length == 2) {
            estadisticasCache.add({
              'fecha': parts[0],
              'total_transferencias': int.tryParse(parts[1]) ?? 0,
            });
          }
        }
        setState(() {
          _estadisticas = estadisticasCache;
        });
      }
    } catch (e) {
      print('Error cargando estadísticas desde caché: $e');
    }
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
        backgroundColor: isError ? AppTheme.error : AppTheme.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
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
          _loadEstadisticas(),
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
      await _cargarEstadisticasDesdeCache();
      
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Cerrar Sesión'),
          content: const Text('¿Estás seguro de que deseas cerrar sesión?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppTheme.error),
              child: const Text('Cerrar Sesión'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
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

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Filtrar por', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              _buildFilterOption(
                icon: Icons.today,
                title: 'Hoy',
                isSelected: _filtroActual == 'hoy',
                onTap: () {
                  setState(() {
                    _filtroActual = 'hoy';
                    _loadTotalData();
                  });
                  Navigator.pop(context);
                },
              ),
              _buildFilterOption(
                icon: Icons.calendar_today,
                title: 'Día específico',
                isSelected: _filtroActual == 'dia',
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
              _buildFilterOption(
                icon: Icons.calendar_month,
                title: 'Mes',
                isSelected: _filtroActual == 'mes',
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
              _buildFilterOption(
                icon: Icons.date_range,
                title: 'Año',
                isSelected: _filtroActual == 'anio',
                onTap: () async {
                  final year = await showDialog<int>(
                    context: context,
                    builder: (context) {
                      int selectedYear = DateTime.now().year;
                      return AlertDialog(
                        title: const Text('Seleccionar año'),
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
                            child: const Text('Cancelar'),
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

  Widget _buildFilterOption({
    required IconData icon,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: isSelected ? AppTheme.green : AppTheme.textSecondary),
      title: Text(title, style: TextStyle(color: isSelected ? AppTheme.green : AppTheme.textPrimary)),
      trailing: isSelected ? Icon(Icons.check, color: AppTheme.green) : null,
      onTap: onTap,
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
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token') ?? '';
  }

  Widget _buildEstadisticasChart() {
    if (_estadisticas.isEmpty) {
      return const SizedBox.shrink();
    }
    
    final dias = _estadisticas.map((e) {
      final fecha = DateTime.parse(e['fecha']);
      return '${fecha.day}/${fecha.month}';
    }).toList();
    
    final valores = _estadisticas.map((e) => (e['total_transferencias'] ?? 0).toDouble()).toList();
    final maxY = valores.isEmpty ? 5 : valores.reduce((a, b) => a > b ? a : b);
    
    return Card(
      elevation: 4,
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.show_chart, color: AppTheme.green, size: 24),
                SizedBox(width: 8),
                Text(
                  'Transferencias - Últimos 7 días',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: AppTheme.border,
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= 0 && index < dias.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                dias[index],
                                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                              ),
                            );
                          }
                          return const Text('');
                        },
                        reservedSize: 30,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          );
                        },
                        reservedSize: 35,
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: AppTheme.border),
                  ),
                  minX: 0,
                  maxX: valores.length.toDouble() - 1,
                  minY: 0,
                  maxY: maxY + 1,
                  lineBarsData: [
                    LineChartBarData(
                      spots: List.generate(valores.length, (index) {
                        return FlSpot(index.toDouble(), valores[index]);
                      }),
                      isCurved: true,
                      color: AppTheme.green,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: AppTheme.green,
                            strokeWidth: 2,
                            strokeColor: Colors.white,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppTheme.green.withOpacity(0.2),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          return LineTooltipItem(
                            '${spot.y.toInt()} transferencias',
                            const TextStyle(color: Colors.white),
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total del período:', style: TextStyle(color: AppTheme.textSecondary)),
                  Text(
                    '${valores.reduce((a, b) => a + b).toInt()} transferencias',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.green),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTransferenciaDetalle(Map<String, dynamic> transferencia) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(child: CircularProgressIndicator());
      },
    );
    
    try {
      final token = await _getValidToken();
      if (token.isEmpty) {
        Navigator.pop(context);
        _showSnack('Error: Sesión expirada', isError: true);
        return;
      }
      
      final response = await _apiService.getTransferenciaById(
        token,
        transferencia['id_transferencia'],
      );
      
      Navigator.pop(context);
      
      if (response['success']) {
        final transferenciaActualizada = response['data'];
        final esDueno = _userData['es_dueno'] ?? false;
        final puedeEditar = transferenciaActualizada['disponible_para_editar'] ?? false;
        final puedeEliminar = esDueno;
        
        _mostrarDialogoDetalle(transferenciaActualizada, esDueno, puedeEditar, puedeEliminar);
      } else {
        _showSnack(response['message'] ?? 'Error al cargar detalles', isError: true);
      }
    } catch (e) {
      Navigator.pop(context);
      _showSnack('Error de conexión: ${e.toString()}', isError: true);
    }
  }

  void _mostrarDialogoDetalle(Map<String, dynamic> transferencia, bool esDueno, bool puedeEditar, bool puedeEliminar) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Detalle de Transferencia', style: TextStyle(color: AppTheme.textPrimary)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetalleRow('Banco:', transferencia['banco'] ?? 'No especificado'),
                const SizedBox(height: 8),
                _buildDetalleRow('Monto:', _formatMonto(transferencia['monto'])),
                const SizedBox(height: 8),
                _buildDetalleRow('Fecha:', _formatFecha(transferencia['fecha_transferencia'])),
                const SizedBox(height: 8),
                _buildDetalleRow('Registrado por:', transferencia['usuario_nombre'] ?? 'Usuario desconocido'),
                const SizedBox(height: 8),
                _buildDetalleRow('Estado:', transferencia['estado'] ?? 'No especificado'),
                if (transferencia['observaciones'] != null && 
                    transferencia['observaciones'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildDetalleRow('Observaciones:', transferencia['observaciones']),
                ],
                if (transferencia['url_comprobante'] != null && 
                    transferencia['url_comprobante'].toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Comprobante:', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
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
                if (!esDueno && !puedeEditar)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.errorBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.timer_off, size: 16, color: AppTheme.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Ya no puedes editar esta transferencia. El tiempo para editarla ha expirado.',
                              style: TextStyle(fontSize: 12, color: AppTheme.error),
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
                icon: const Icon(Icons.edit, color: AppTheme.green),
                label: const Text('Editar', style: TextStyle(color: AppTheme.green)),
              ),
            if (puedeEliminar)
              TextButton.icon(
                onPressed: () async {
                  final token = await _getValidToken();
                  if (token.isEmpty) return;
                  _confirmarEliminar(transferencia, token);
                },
                icon: const Icon(Icons.delete, color: AppTheme.error),
                label: const Text('Eliminar', style: TextStyle(color: AppTheme.error)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
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
          backgroundColor: AppTheme.surface,
          title: const Text('Eliminar Transferencia', style: TextStyle(color: AppTheme.textPrimary)),
          content: const Text('¿Estás seguro de que deseas eliminar esta transferencia? Esta acción no se puede deshacer.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppTheme.error),
              child: const Text('Eliminar'),
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
        final response = await _apiService.eliminarTransferencia(
          token,
          transferencia['id_transferencia'],
        );
        
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
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
        const SizedBox(width: 8),
        Expanded(child: Text(value, style: const TextStyle(color: AppTheme.textPrimary))),
      ],
    );
  }

  void _showComprobanteImagen(String url) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: AppTheme.surface,
          child: Container(
            width: double.maxFinite,
            height: 500,
            child: Column(
              children: [
                AppBar(
                  title: const Text('Comprobante'),
                  backgroundColor: AppTheme.green,
                  foregroundColor: Colors.white,
                  automaticallyImplyLeading: false,
                  actions: [
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                Expanded(
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                    errorWidget: (context, url, error) => Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
                          const SizedBox(height: 16),
                          const Text('No se pudo cargar la imagen', style: TextStyle(color: AppTheme.textSecondary)),
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
          placeholder: (context, url) => Container(width: size, height: size, child: const CircularProgressIndicator()),
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

  @override
  Widget build(BuildContext context) {
    final String fotoPerfilUrl = _userData['foto_perfil_url'] ?? _userData['fotoPerfilUrl'] ?? '';
    final bool tieneFoto = _userData['tiene_foto_perfil'] ?? false;

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: Row(
          children: [
            const Text("PillaPago", style: TextStyle(color: AppTheme.textPrimary)),
            const SizedBox(width: 8),
            // Indicador de conexión
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isOnline ? AppTheme.green : AppTheme.error,
              ),
            ),
            // Indicador de modo offline para notificaciones
            if (_isOfflineMode && !_isOnline) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.warning,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Offline',
                  style: TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          // Botón de transferencias pendientes
          ValueListenableBuilder<int>(
            valueListenable: _pendingCountNotifier,
            builder: (context, pendingCount, child) {
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.pending_actions, color: AppTheme.textPrimary),
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
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: AppTheme.error,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          '$pendingCount',
                          style: const TextStyle(color: Colors.white, fontSize: 10),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          
          // Botón de NOTIFICACIONES con badge y modo offline
          Stack(
            children: [
              IconButton(
                icon: Stack(
                  children: [
                    const Icon(Icons.notifications_none, color: AppTheme.textPrimary),
                    // Indicador de modo offline en el icono
                    if (_isOfflineMode && !_isOnline)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppTheme.warning,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.surface, width: 1),
                          ),
                        ),
                      ),
                  ],
                ),
                onPressed: () async {
                  final token = await _getValidToken();
                  if (token.isEmpty) {
                    _showSnack('Error: No hay sesión activa', isError: true);
                    return;
                  }
                  
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NotificationsScreen(token: token),
                    ),
                  );
                  
                  // Recargar contador al volver
                  await _loadNotificationCount();
                },
              ),
              if (_notificationCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AppTheme.error,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      _notificationCount > 99 ? '99+' : '$_notificationCount',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          
          // Botón de settings
          IconButton(
            icon: const Icon(Icons.settings, color: AppTheme.textPrimary),
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
            color: AppTheme.green,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty && _transferencias.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, size: 64, color: AppTheme.error),
                            const SizedBox(height: 16),
                            Text(_errorMessage, style: const TextStyle(color: AppTheme.error)),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadAllData,
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
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _buildProfileImage(fotoPerfilUrl, tieneFoto, _userData['nombre']),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Hola, ${_userData['nombre']?.split(' ')[0] ?? 'Usuario'}',
                                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                      ),
                                      Text(
                                        _userData['nombre_negocio'] ?? 'Sin negocio',
                                        style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Card(
                              color: AppTheme.surface,
                              elevation: 4,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: InkWell(
                                onTap: _showFilterDialog,
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('Total', style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: AppTheme.green.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Row(
                                              children: [
                                                Text(_getPeriodoTexto(), style: const TextStyle(color: AppTheme.green, fontWeight: FontWeight.w500)),
                                                const SizedBox(width: 4),
                                                const Icon(Icons.arrow_drop_down, color: AppTheme.green),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        _formatMonto(_totalData['total'] ?? 0),
                                        style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: AppTheme.green),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _totalData['moneda'] ?? 'USD',
                                        style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
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
                                icon: const Icon(Icons.add_circle_outline),
                                label: const Text('Añadir Transferencia', style: TextStyle(fontSize: 16)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            if (!_isLoadingEstadisticas && _estadisticas.isNotEmpty)
                              _buildEstadisticasChart(),
                            if (_isLoadingEstadisticas)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Center(child: CircularProgressIndicator()),
                              ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Historial', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                                if (_transferencias.isNotEmpty)
                                  Text(
                                    '${_transferencias.length} registros',
                                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _transferencias.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(40),
                                      child: Column(
                                        children: [
                                          const Icon(Icons.history, size: 64, color: AppTheme.textSecondary),
                                          const SizedBox(height: 16),
                                          const Text('No hay transferencias registradas', style: TextStyle(color: AppTheme.textSecondary)),
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: _transferencias.length + (_isLoadingMore ? 1 : 0),
                                    itemBuilder: (context, index) {
                                      if (index == _transferencias.length && _isLoadingMore) {
                                        return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                                      }
                                      final transferencia = _transferencias[index];
                                      return Card(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        color: AppTheme.surface,
                                        elevation: 2,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        child: InkWell(
                                          onTap: () => _showTransferenciaDetalle(transferencia),
                                          borderRadius: BorderRadius.circular(12),
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Row(
                                                    children: [
                                                      CircleAvatar(
                                                        backgroundColor: AppTheme.surfaceLight,
                                                        radius: 20,
                                                        child: Icon(Icons.account_balance, color: AppTheme.green, size: 20),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text(
                                                              transferencia['banco'] ?? 'Banco no especificado',
                                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary),
                                                            ),
                                                            Row(
                                                              children: [
                                                                const Icon(Icons.person, size: 12, color: AppTheme.textSecondary),
                                                                const SizedBox(width: 4),
                                                                Expanded(
                                                                  child: Text(
                                                                    transferencia['usuario_nombre'] ?? transferencia['nombre_usuario'] ?? 'Usuario desconocido',
                                                                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                                                    maxLines: 1,
                                                                    overflow: TextOverflow.ellipsis,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                            if (transferencia['observaciones'] != null && transferencia['observaciones'].toString().isNotEmpty)
                                                              Text(
                                                                transferencia['observaciones'],
                                                                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                                                maxLines: 1,
                                                                overflow: TextOverflow.ellipsis,
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.end,
                                                  children: [
                                                    Text(
                                                      _formatMonto(transferencia['monto']),
                                                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.green, fontSize: 16),
                                                    ),
                                                    Text(
                                                      _formatFecha(transferencia['fecha_transferencia']),
                                                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                                    ),
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
                backgroundColor: AppTheme.green,
                child: const Icon(Icons.arrow_upward, color: Colors.white),
                elevation: 4,
              ),
            ),
        ],
      ),
    );
  }
}