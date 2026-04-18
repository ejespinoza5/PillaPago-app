// lib/services/notification_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'database_service.dart';
import '../models/notificacion.dart';

class NotificationService {
  final String token;
  final DatabaseService _dbService = DatabaseService();
  
  NotificationService({required this.token});

  // Helper para hacer peticiones usando el método de ApiService
  Future<Map<String, dynamic>> _requestWithAuth(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final currentToken = await ApiService.getAccessToken();
    
    if (currentToken != token) {
      await ApiService.saveTokens(token, await ApiService.getRefreshToken() ?? '');
    }
    
    return await ApiService.requestWithAuth(method, endpoint, body: body);
  }

  // 1. Obtener notificaciones (con soporte offline)
  Future<NotificacionesResponse> getNotificaciones({
    int page = 1,
    int limit = 20,
    bool soloNoLeidas = false,
    bool forceOnline = false,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
        if (soloNoLeidas) 'solo_no_leidas': 'true',
      };
      
      final queryString = queryParams.entries.map((e) => '${e.key}=${e.value}').join('&');
      final endpoint = '/api/notificaciones${queryString.isNotEmpty ? '?$queryString' : ''}';
      
      final response = await _requestWithAuth('GET', endpoint);
      
      if (response['success'] && response['data'] != null) {
        // Guardar en caché local
        final notificacionesData = response['data']['data'] ?? [];
        await _dbService.guardarNotificaciones(notificacionesData);
        
        return NotificacionesResponse.fromJson(response['data']);
      } else if (response['unauthorized'] == true) {
        throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.');
      } else {
        throw Exception(response['message'] ?? 'Error al obtener notificaciones');
      }
    } catch (e) {
      // Si hay error de conexión, intentar cargar desde caché
      final errorStr = e.toString();
      if (!forceOnline && (errorStr.contains('SocketException') || 
          errorStr.contains('Connection refused') ||
          errorStr.contains('Timeout') ||
          errorStr.contains('Failed to connect'))) {
        
        if (kDebugMode) {
          if (kDebugMode) print('�x� Modo offline - Cargando notificaciones desde caché');
        }
        
        final cachedData = await _dbService.getNotificacionesCache(
          soloNoLeidas: soloNoLeidas,
          page: page,
          limit: limit,
        );
        
        final unreadCount = await _dbService.getNotificacionesNoLeidasCountCache();
        
        // Convertir datos de caché al formato esperado
        final notificaciones = cachedData.map((item) => Notificacion(
          idNotificacion: item['id_notificacion'],
          idDestinatario: item['id_destinatario'],
          idActor: item['id_actor'],
          idNegocio: item['id_negocio'],
          tipo: item['tipo'] ?? '',
          titulo: item['titulo'] ?? '',
          mensaje: item['mensaje'] ?? '',
          payload: item['payload'] != null ? jsonDecode(item['payload']) : null,
          leida: item['leida'] == 1,
          createdAt: DateTime.parse(item['created_at']),
          actorNombre: item['actor_nombre'],
        )).toList();
        
        return NotificacionesResponse(
          data: notificaciones,
          unreadCount: unreadCount,
          pagination: PaginationInfo(
            page: page,
            limit: limit,
            total: notificaciones.length,
            totalPages: 1,
            hasNextPage: false,
            hasPrevPage: false,
          ),
        );
      }
      throw Exception('Error de conexión: $e');
    }
  }

  // 2. Obtener solo el contador de no leídas (con soporte offline)
  Future<int> getUnreadCount() async {
    try {
      final response = await getNotificaciones(page: 1, limit: 1, soloNoLeidas: true);
      return response.unreadCount;
    } catch (e) {
      // Si hay error, intentar desde caché
      return await _dbService.getNotificacionesNoLeidasCountCache();
    }
  }

  // 3. Marcar notificación como leída (con soporte offline)
  Future<Map<String, dynamic>> marcarComoLeida(int idNotificacion) async {
    try {
      final response = await _requestWithAuth(
        'PATCH',
        '/api/notificaciones/$idNotificacion/leida',
      );
      
      if (response['success']) {
        // Actualizar caché local
        await _dbService.marcarNotificacionLeidaCache(idNotificacion);
        return response['data'] ?? {'message': 'Notificación marcada como leída'};
      } else if (response['unauthorized'] == true) {
        throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.');
      } else {
        throw Exception(response['message'] ?? 'Error al marcar como leída');
      }
    } catch (e) {
      final errorStr = e.toString();
      // Si hay error de conexión, guardar acción pendiente
      if (errorStr.contains('SocketException') || 
          errorStr.contains('Connection refused') ||
          errorStr.contains('Timeout')) {
        
        if (kDebugMode) {
          if (kDebugMode) print('�x� Modo offline - Marcando localmente como leída');
        }
        
        // Marcar localmente en caché
        await _dbService.marcarNotificacionLeidaCache(idNotificacion);
        
        // Guardar en cola de sincronización para cuando vuelva online
        await _dbService.guardarAccionPendiente('marcar_leida', {'id': idNotificacion});
        
        return {'message': 'Notificación marcada como leída (se sincronizará al recuperar conexión)'};
      }
      throw Exception('Error de conexión: $e');
    }
  }

  // 4. Marcar todas como leídas (con soporte offline)
  Future<Map<String, dynamic>> marcarTodasComoLeidas() async {
    try {
      final response = await _requestWithAuth(
        'PATCH',
        '/api/notificaciones/leidas/todas',
      );
      
      if (response['success']) {
        // Actualizar caché local
        final updatedCount = await _dbService.marcarTodasNotificacionesLeidasCache();
        return {'updated_count': updatedCount, 'message': 'Todas marcadas como leídas'};
      } else if (response['unauthorized'] == true) {
        throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.');
      } else {
        throw Exception(response['message'] ?? 'Error al marcar todas');
      }
    } catch (e) {
      final errorStr = e.toString();
      // Si hay error de conexión
      if (errorStr.contains('SocketException') || 
          errorStr.contains('Connection refused') ||
          errorStr.contains('Timeout')) {
        
        if (kDebugMode) {
          if (kDebugMode) print('�x� Modo offline - Marcando todas localmente');
        }
        
        final updatedCount = await _dbService.marcarTodasNotificacionesLeidasCache();
        await _dbService.guardarAccionPendiente('marcar_todas', {});
        
        return {'updated_count': updatedCount, 'message': 'Todas marcadas como leídas (se sincronizará al recuperar conexión)'};
      }
      throw Exception('Error de conexión: $e');
    }
  }

  // 5. Sincronizar acciones pendientes (llamar cuando vuelva online)
  Future<int> sincronizarAccionesPendientes() async {
    final acciones = await _dbService.getAccionesPendientes();
    
    if (acciones.isEmpty) {
      if (kDebugMode) print('�x� No hay acciones pendientes para sincronizar');
      return 0;
    }
    
    if (kDebugMode) print('�x� Sincronizando ${acciones.length} acciones pendientes...');
    
    int sincronizadas = 0;
    for (var accion in acciones) {
      try {
        final tipo = accion['tipo'];
        final datos = jsonDecode(accion['datos']);
        
        if (tipo == 'marcar_leida') {
          await _requestWithAuth('PATCH', '/api/notificaciones/${datos['id']}/leida');
          sincronizadas++;
        } else if (tipo == 'marcar_todas') {
          await _requestWithAuth('PATCH', '/api/notificaciones/leidas/todas');
          sincronizadas++;
        }
        
        // Marcar como sincronizada
        await _dbService.marcarAccionSincronizada(accion['id']);
        
        if (kDebugMode) {
          if (kDebugMode) print('�S& Acción $tipo sincronizada correctamente');
        }
      } catch (e) {
        if (kDebugMode) {
          if (kDebugMode) print('�R Error sincronizando acción ${accion['id']}: $e');
        }
      }
    }
    
    if (kDebugMode) {
      if (kDebugMode) print('�S& $sincronizadas acciones pendientes sincronizadas');
    }
    return sincronizadas;
  }

  // 6. Registrar token de dispositivo (FCM)
  Future<Map<String, dynamic>> registrarDeviceToken(String fcmToken, String plataforma) async {
    try {
      final response = await _requestWithAuth(
        'POST',
        '/api/device-tokens',
        body: {
          'token': fcmToken,
          'plataforma': plataforma,
        },
      );
      
      if (response['success']) {
        return response['data'] ?? {'message': 'Token registrado correctamente'};
      } else if (response['unauthorized'] == true) {
        throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.');
      } else {
        throw Exception(response['message'] ?? 'Error al registrar token');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  // 7. Desactivar token de dispositivo
  Future<Map<String, dynamic>> desactivarDeviceToken(String fcmToken) async {
    try {
      final response = await _requestWithAuth(
        'DELETE',
        '/api/device-tokens',
        body: {'token': fcmToken},
      );
      
      if (response['success']) {
        return response['data'] ?? {'message': 'Token desactivado correctamente'};
      } else if (response['unauthorized'] == true) {
        throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.');
      } else {
        throw Exception(response['message'] ?? 'Error al desactivar token');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  // 8. Obtener mis tokens activos
  Future<List<DeviceToken>> getMisDeviceTokens() async {
    try {
      final response = await _requestWithAuth('GET', '/api/device-tokens');
      
      if (response['success'] && response['data'] != null) {
        final data = response['data'];
        final List<dynamic> tokens = data['data'] ?? [];
        return tokens.map((token) => DeviceToken.fromJson(token)).toList();
      } else if (response['unauthorized'] == true) {
        throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.');
      } else {
        throw Exception(response['message'] ?? 'Error al obtener tokens');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }
}
