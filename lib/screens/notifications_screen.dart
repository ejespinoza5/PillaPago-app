// lib/screens/notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/notification_service.dart';
import '../services/notification_counter_service.dart';
import '../models/notificacion.dart';
import '../theme/app_theme.dart';

class NotificationsScreen extends StatefulWidget {
  final String token;

  const NotificationsScreen({Key? key, required this.token}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late NotificationService _notificationService;
  List<Notificacion> _notificaciones = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String _errorMessage = '';
  int _unreadCount = 0;
  
  int _currentPage = 1;
  int _totalPages = 1;
  bool _hasMorePages = true;
  final int _limit = 20;
  bool _soloNoLeidas = false;
  
  late ScrollController _scrollController;
  bool _isOfflineMode = false;

  @override
  void initState() {
    super.initState();
    
    if (kDebugMode) {
      debugPrint("🚀 ========== NOTIFICATIONS SCREEN INIT ==========");
    }
    
    final tokenPreview = widget.token.length > 30 
        ? widget.token.substring(0, 30) 
        : widget.token;
    
    if (kDebugMode) {
      debugPrint("🔑 Token recibido: $tokenPreview...");
      debugPrint("📱 Token longitud: ${widget.token.length}");
    }
    
    if (widget.token.isEmpty) {
      if (kDebugMode) debugPrint("❌ Token vacío!");
      _errorMessage = 'Token de autenticación no válido';
      _isLoading = false;
      return;
    }
    
    _notificationService = NotificationService(token: widget.token);
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    
    if (kDebugMode) debugPrint("📡 Llamando a _loadNotificaciones...");
    _loadNotificaciones();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 100) {
      if (_hasMorePages && !_isLoadingMore && !_isLoading) {
        _loadMoreNotificaciones();
      }
    }
  }

  Future<void> _loadNotificaciones({bool reset = true}) async {
    if (kDebugMode) debugPrint("🔄 _loadNotificaciones - reset: $reset");
    
    if (reset) {
      setState(() {
        _isLoading = true;
        _currentPage = 1;
        _notificaciones = [];
        _hasMorePages = true;
        _errorMessage = '';
        _isOfflineMode = false;
      });
    }

    try {
      if (kDebugMode) debugPrint("📡 Haciendo petición a getNotificaciones...");
      final response = await _notificationService.getNotificaciones(
        page: _currentPage,
        limit: _limit,
        soloNoLeidas: _soloNoLeidas,
      );
      
      if (kDebugMode) {
        debugPrint("✅ Respuesta recibida. Notificaciones: ${response.data.length}");
        debugPrint("📊 No leídas: ${response.unreadCount}");
      }
      
      if (mounted) {
        setState(() {
          if (reset) {
            _notificaciones = response.data;
          } else {
            _notificaciones.addAll(response.data);
          }
          _unreadCount = response.unreadCount;
          _totalPages = response.pagination.totalPages;
          _hasMorePages = response.pagination.hasNextPage;
          
          if (_hasMorePages && !reset) {
            _currentPage++;
          }
          
          _isLoading = false;
          _isLoadingMore = false;
          _isOfflineMode = false;
        });
        if (kDebugMode) debugPrint("✅ Estado actualizado. Total notificaciones: ${_notificaciones.length}");
      }
    } catch (e) {
      final errorStr = e.toString();
      if (kDebugMode) debugPrint("❌ ERROR en _loadNotificaciones: $e");
      
      // Verificar si es modo offline
      final isOffline = errorStr.contains('SocketException') || 
                        errorStr.contains('Connection refused') ||
                        errorStr.contains('Timeout') ||
                        errorStr.contains('Failed to connect');
      
      setState(() {
        _errorMessage = isOffline ? 'Sin conexión. Mostrando notificaciones guardadas.' : errorStr;
        _isLoading = false;
        _isLoadingMore = false;
        _isOfflineMode = isOffline;
      });
      
      // Si es offline y no hay notificaciones, mostrar mensaje amigable
      if (isOffline && _notificaciones.isEmpty) {
        _errorMessage = 'Sin conexión a internet. Las notificaciones se actualizarán cuando recuperes conexión.';
      }
    }
  }

  Future<void> _loadMoreNotificaciones() async {
    if (!_hasMorePages || _isLoadingMore || _isLoading) return;
    
    setState(() {
      _isLoadingMore = true;
    });
    
    await _loadNotificaciones(reset: false);
  }

  Future<void> _marcarComoLeida(Notificacion notificacion) async {
    if (notificacion.leida) return;
    
    // Guardar estado anterior para posible revertir
    final previousLeida = notificacion.leida;
    final previousUnreadCount = _unreadCount;
    
    // Optimistic update
    setState(() {
      final index = _notificaciones.indexWhere((n) => n.idNotificacion == notificacion.idNotificacion);
      if (index != -1) {
        _notificaciones[index].leida = true;
        _unreadCount--;
      }
    });
    
    // Actualizar contador global
    NotificationCounterService.decrementCounter();
    
    try {
      await _notificationService.marcarComoLeida(notificacion.idNotificacion);
      if (kDebugMode) debugPrint("✅ Notificación ${notificacion.idNotificacion} marcada como leída");
    } catch (e) {
      // Revertir en caso de error
      setState(() {
        final index = _notificaciones.indexWhere((n) => n.idNotificacion == notificacion.idNotificacion);
        if (index != -1) {
          _notificaciones[index].leida = previousLeida;
          _unreadCount = previousUnreadCount;
        }
      });
      NotificationCounterService.incrementCounter();
      
      final isOffline = e.toString().contains('SocketException') || 
                        e.toString().contains('Connection refused');
      
      if (isOffline) {
        _showSnack('Marcada como leída (modo offline - se sincronizará después)', isError: false);
      } else {
        _showSnack('Error al marcar como leída: $e', isError: true);
      }
    }
  }

  Future<void> _marcarTodasComoLeidas() async {
    if (_unreadCount == 0) return;
    
    // Guardar estado anterior
    final previousNotificaciones = List<Notificacion>.from(_notificaciones);
    final previousUnreadCount = _unreadCount;
    
    // Optimistic update
    setState(() {
      for (var notificacion in _notificaciones) {
        notificacion.leida = true;
      }
      _unreadCount = 0;
    });
    
    // Resetear contador global
    NotificationCounterService.resetCounter();
    
    try {
      final result = await _notificationService.marcarTodasComoLeidas();
      final updatedCount = result['updated_count'] ?? 0;
      _showSnack('$updatedCount notificaciones marcadas como leídas');
      if (kDebugMode) debugPrint("✅ Todas las notificaciones marcadas como leídas");
    } catch (e) {
      // Revertir en caso de error
      setState(() {
        _notificaciones = previousNotificaciones;
        _unreadCount = previousUnreadCount;
      });
      // Revertir contador global
      for (int i = 0; i < previousUnreadCount; i++) {
        NotificationCounterService.incrementCounter();
      }
      
      final isOffline = e.toString().contains('SocketException') || 
                        e.toString().contains('Connection refused');
      
      if (isOffline) {
        _showSnack('Todas marcadas como leídas (modo offline - se sincronizará después)', isError: false);
      } else {
        _showSnack('Error al marcar todas: $e', isError: true);
      }
    }
  }

  Future<void> _refreshNotificaciones() async {
    _currentPage = 1;
    await _loadNotificaciones(reset: true);
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppTheme.error : AppTheme.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  void _toggleFilter() {
    setState(() {
      _soloNoLeidas = !_soloNoLeidas;
      _refreshNotificaciones();
    });
  }

  String _formatFecha(DateTime fecha) {
    final now = DateTime.now();
    final diff = now.difference(fecha);
    
    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        if (diff.inMinutes == 0) {
          return 'Ahora mismo';
        }
        return 'Hace ${diff.inMinutes} min';
      }
      return 'Hace ${diff.inHours} h';
    } else if (diff.inDays == 1) {
      return 'Ayer';
    } else if (diff.inDays < 7) {
      return 'Hace ${diff.inDays} días';
    } else {
      return '${fecha.day}/${fecha.month}/${fecha.year}';
    }
  }

  IconData _getIconForTipo(String tipo) {
    switch (tipo) {
      case 'bienvenida_dueno':
      case 'bienvenida_empleado':
        return Icons.celebration;
      case 'empleado_registrado':
        return Icons.person_add;
      case 'transferencia_creada':
        return Icons.attach_money;
      case 'seguridad_password_cambiado':
        return Icons.lock_reset;
      case 'seguridad_email_cambiado':
        return Icons.email;
      case 'seguridad_email_verificado':
        return Icons.verified;
      default:
        return Icons.notifications;
    }
  }

  Color _getColorForTipo(String tipo) {
    if (tipo.startsWith('bienvenida')) return AppTheme.green;
    if (tipo.startsWith('seguridad')) return AppTheme.warning;
    if (tipo == 'transferencia_creada') return AppTheme.info;
    return AppTheme.green;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Notificaciones', style: TextStyle(color: AppTheme.textPrimary)),
            if (_unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.error,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_unreadCount',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            if (_isOfflineMode)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.warning,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_off, size: 12, color: Colors.white),
                    SizedBox(width: 2),
                    Text('Offline', style: TextStyle(color: Colors.white, fontSize: 10)),
                  ],
                ),
              ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _soloNoLeidas ? Icons.filter_alt : Icons.filter_alt_outlined,
              color: _soloNoLeidas ? AppTheme.green : AppTheme.textSecondary,
            ),
            onPressed: _toggleFilter,
            tooltip: _soloNoLeidas ? 'Mostrar todas' : 'Solo no leídas',
          ),
          if (_unreadCount > 0)
            IconButton(
              icon: const Icon(Icons.done_all, color: AppTheme.textPrimary),
              onPressed: _marcarTodasComoLeidas,
              tooltip: 'Marcar todas como leídas',
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshNotificaciones,
        color: AppTheme.green,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage.isNotEmpty && _notificaciones.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isOfflineMode ? Icons.wifi_off : Icons.notifications_off,
                          size: 64,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage,
                          style: const TextStyle(color: AppTheme.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        if (!_isOfflineMode)
                          ElevatedButton(
                            onPressed: _refreshNotificaciones,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.green,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Reintentar'),
                          ),
                        if (_isOfflineMode)
                          ElevatedButton.icon(
                            onPressed: () async {
                              // Intentar reconectar
                              _refreshNotificaciones();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reconectar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  )
                : _notificaciones.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _soloNoLeidas ? Icons.check_circle_outline : Icons.notifications_none,
                              size: 64,
                              color: AppTheme.textSecondary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _soloNoLeidas 
                                  ? 'No tienes notificaciones no leídas'
                                  : 'No tienes notificaciones',
                              style: const TextStyle(color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: _notificaciones.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _notificaciones.length && _isLoadingMore) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          
                          final notificacion = _notificaciones[index];
                          return _buildNotificationCard(notificacion);
                        },
                      ),
      ),
    );
  }

  Widget _buildNotificationCard(Notificacion notificacion) {
    return GestureDetector(
      onTap: () => _marcarComoLeida(notificacion),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: notificacion.leida 
              ? AppTheme.surface 
              : AppTheme.surface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
          border: !notificacion.leida
              ? Border.all(color: AppTheme.green, width: 1.5)
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _getColorForTipo(notificacion.tipo).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getIconForTipo(notificacion.tipo),
                  color: _getColorForTipo(notificacion.tipo),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notificacion.titulo,
                      style: TextStyle(
                        fontWeight: notificacion.leida ? FontWeight.normal : FontWeight.bold,
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notificacion.mensaje,
                      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                    ),
                    if (notificacion.actorNombre != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.person, size: 12, color: AppTheme.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            notificacion.actorNombre!,
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      _formatFecha(notificacion.createdAt),
                      style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              if (!notificacion.leida)
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppTheme.green,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}