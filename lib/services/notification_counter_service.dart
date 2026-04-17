// lib/services/notification_counter_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'notification_service.dart';
import 'database_service.dart';

class NotificationCounterService {
  static int _unreadCount = 0;
  static final List<void Function(int)> _listeners = [];
  static bool _isLoading = false;
  static DatabaseService? _dbService;
  
  // Getters
  static int get unreadCount => _unreadCount;
  static bool get isLoading => _isLoading;
  
  // Inicializar servicio (llamar al inicio de la app)
  static Future<void> init() async {
    _dbService = DatabaseService();
    await _loadFromCache();
  }
  
  // Obtener DatabaseService
  static Future<DatabaseService> get _getDbService async {
    _dbService ??= DatabaseService();
    return _dbService!;
  }
  
  // Agregar listener
  static void addListener(void Function(int) listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }
  
  // Remover listener
  static void removeListener(void Function(int) listener) {
    _listeners.remove(listener);
  }
  
  // Notificar a todos los listeners
  static void _notifyListeners() {
    for (var listener in _listeners) {
      listener(_unreadCount);
    }
  }
  
  // Cargar desde caché local (SharedPreferences)
  static Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _unreadCount = prefs.getInt('unread_notifications_count') ?? 0;
      if (kDebugMode) print("📱 Contador cargado desde caché: $_unreadCount");
      _notifyListeners();
    } catch (e) {
      if (kDebugMode) print("Error cargando contador desde caché: $e");
      _unreadCount = 0;
    }
  }
  
  // Cargar contador desde el servidor (con soporte offline)
  static Future<void> loadUnreadCount(String token, {bool forceOnline = false}) async {
    if (_isLoading) return;
    _isLoading = true;
    
    try {
      // Intentar cargar desde el servidor
      final service = NotificationService(token: token);
      final serverCount = await service.getUnreadCount();
      
      _unreadCount = serverCount;
      _notifyListeners();
      
      // Guardar en caché local
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('unread_notifications_count', _unreadCount);
      
      // También guardar en base de datos local
      final db = await _getDbService;
      await db.guardarContadorNotificaciones(_unreadCount);
      
      if (kDebugMode) print("✅ Contador cargado desde servidor: $_unreadCount");
      
    } catch (e) {
      final errorStr = e.toString();
      final isOffline = errorStr.contains('SocketException') || 
                        errorStr.contains('Connection refused') ||
                        errorStr.contains('Timeout') ||
                        errorStr.contains('Failed to connect');
      
      if (isOffline && !forceOnline) {
        // Modo offline - usar caché
        if (kDebugMode) print("📱 Modo offline - usando contador en caché: $_unreadCount");
        
        // Intentar cargar desde base de datos local
        try {
          final db = await _getDbService;
          final dbCount = await db.getContadorNotificaciones();
          if (dbCount != null && dbCount > 0) {
            _unreadCount = dbCount;
            _notifyListeners();
            if (kDebugMode) print("📱 Contador cargado desde base de datos local: $_unreadCount");
          }
        } catch (dbError) {
          if (kDebugMode) print("Error cargando contador desde BD: $dbError");
        }
      } else {
        if (kDebugMode) print("❌ Error cargando contador: $e");
      }
    } finally {
      _isLoading = false;
    }
  }
  
  // Incrementar contador (cuando llega nueva notificación)
  static Future<void> incrementCounter() async {
    _unreadCount++;
    _notifyListeners();
    
    // Guardar en caché
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('unread_notifications_count', _unreadCount);
    
    // Guardar en base de datos local
    try {
      final db = await _getDbService;
      await db.guardarContadorNotificaciones(_unreadCount);
    } catch (e) {
      if (kDebugMode) print("Error guardando contador en BD: $e");
    }
    
    if (kDebugMode) print("🔔 Contador incrementado: $_unreadCount");
  }
  
  // Decrementar contador (cuando se lee una notificación)
  static Future<void> decrementCounter() async {
    if (_unreadCount > 0) {
      _unreadCount--;
      _notifyListeners();
      
      // Guardar en caché
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('unread_notifications_count', _unreadCount);
      
      // Guardar en base de datos local
      try {
        final db = await _getDbService;
        await db.guardarContadorNotificaciones(_unreadCount);
      } catch (e) {
        if (kDebugMode) print("Error guardando contador en BD: $e");
      }
      
      if (kDebugMode) print("🔔 Contador decrementado: $_unreadCount");
    }
  }
  
  // Resetear contador a cero
  static Future<void> resetCounter() async {
    _unreadCount = 0;
    _notifyListeners();
    
    // Guardar en caché
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('unread_notifications_count', 0);
    
    // Guardar en base de datos local
    try {
      final db = await _getDbService;
      await db.guardarContadorNotificaciones(0);
    } catch (e) {
      if (kDebugMode) print("Error guardando contador en BD: $e");
    }
    
    if (kDebugMode) print("🔔 Contador resetado: 0");
  }
  
  // Actualizar contador manualmente
  static Future<void> updateCounter(int newCount) async {
    if (_unreadCount == newCount) return;
    
    _unreadCount = newCount;
    _notifyListeners();
    
    // Guardar en caché
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('unread_notifications_count', _unreadCount);
    
    // Guardar en base de datos local
    try {
      final db = await _getDbService;
      await db.guardarContadorNotificaciones(_unreadCount);
    } catch (e) {
      if (kDebugMode) print("Error guardando contador en BD: $e");
    }
    
    if (kDebugMode) print("🔔 Contador actualizado: $_unreadCount");
  }
  
  // Sincronizar contador con el servidor (útil cuando vuelve online)
  static Future<void> syncWithServer(String token) async {
    if (_isLoading) return;
    _isLoading = true;
    
    try {
      final service = NotificationService(token: token);
      final serverCount = await service.getUnreadCount();
      
      if (_unreadCount != serverCount) {
        if (kDebugMode) print("🔄 Sincronizando contador: local=$_unreadCount, servidor=$serverCount");
        _unreadCount = serverCount;
        _notifyListeners();
        
        // Guardar en caché
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('unread_notifications_count', _unreadCount);
        
        // Guardar en base de datos local
        final db = await _getDbService;
        await db.guardarContadorNotificaciones(_unreadCount);
      }
      
      if (kDebugMode) print("✅ Contador sincronizado: $_unreadCount");
      
    } catch (e) {
      if (kDebugMode) print("❌ Error sincronizando contador: $e");
    } finally {
      _isLoading = false;
    }
  }
  
  // Obtener estado actual (para debugging)
  static Future<Map<String, dynamic>> getStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedCount = prefs.getInt('unread_notifications_count') ?? 0;
    
    int? dbCount;
    try {
      final db = await _getDbService;
      dbCount = await db.getContadorNotificaciones();
    } catch (e) {
      if (kDebugMode) print("Error obteniendo contador de BD: $e");
    }
    
    return {
      'memoryCount': _unreadCount,
      'cachedCount': cachedCount,
      'dbCount': dbCount,
      'isLoading': _isLoading,
    };
  }
}