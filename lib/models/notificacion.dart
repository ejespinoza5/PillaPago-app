// lib/models/notificacion.dart
class Notificacion {
  final int idNotificacion;
  final int idDestinatario;
  final int? idActor;
  final int? idNegocio;
  final String tipo;
  final String titulo;
  final String mensaje;
  final Map<String, dynamic>? payload;
  bool leida;
  final DateTime createdAt;
  final String? actorNombre;

  Notificacion({
    required this.idNotificacion,
    required this.idDestinatario,
    this.idActor,
    this.idNegocio,
    required this.tipo,
    required this.titulo,
    required this.mensaje,
    this.payload,
    required this.leida,
    required this.createdAt,
    this.actorNombre,
  });

  factory Notificacion.fromJson(Map<String, dynamic> json) {
    // ✅ Función helper para convertir a int de forma segura
    int _toInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return Notificacion(
      idNotificacion: _toInt(json['id_notificacion']),
      idDestinatario: _toInt(json['id_destinatario']),
      idActor: json['id_actor'] != null ? _toInt(json['id_actor']) : null,
      idNegocio: json['id_negocio'] != null ? _toInt(json['id_negocio']) : null,
      tipo: json['tipo']?.toString() ?? '',
      titulo: json['titulo']?.toString() ?? '',
      mensaje: json['mensaje']?.toString() ?? '',
      payload: json['payload'] is Map ? Map<String, dynamic>.from(json['payload']) : null,
      leida: json['leida'] == true || json['leida'] == 'true' || json['leida'] == 1,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'].toString()) 
          : DateTime.now(),
      actorNombre: json['actor_nombre']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id_notificacion': idNotificacion,
      'id_destinatario': idDestinatario,
      'id_actor': idActor,
      'id_negocio': idNegocio,
      'tipo': tipo,
      'titulo': titulo,
      'mensaje': mensaje,
      'payload': payload,
      'leida': leida,
      'created_at': createdAt.toIso8601String(),
      'actor_nombre': actorNombre,
    };
  }
}

class NotificacionesResponse {
  final List<Notificacion> data;
  final int unreadCount;
  final PaginationInfo pagination;

  NotificacionesResponse({
    required this.data,
    required this.unreadCount,
    required this.pagination,
  });

  factory NotificacionesResponse.fromJson(Map<String, dynamic> json) {
    // ✅ Función helper para convertir a int
    int _toInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return NotificacionesResponse(
      data: (json['data'] as List?)
              ?.map((item) => Notificacion.fromJson(item))
              .toList() ?? [],
      unreadCount: _toInt(json['unread_count']),
      pagination: PaginationInfo.fromJson(json['pagination'] ?? {}),
    );
  }
}

class PaginationInfo {
  final int page;
  final int limit;
  final int total;
  final int totalPages;
  final bool hasNextPage;
  final bool hasPrevPage;

  PaginationInfo({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
    required this.hasNextPage,
    required this.hasPrevPage,
  });

  factory PaginationInfo.fromJson(Map<String, dynamic> json) {
    // ✅ Función helper para convertir a int
    int _toInt(dynamic value) {
      if (value == null) return 1;
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 1;
      return 1;
    }
    
    bool _toBool(dynamic value) {
      if (value == null) return false;
      if (value is bool) return value;
      if (value is String) return value.toLowerCase() == 'true';
      return false;
    }

    return PaginationInfo(
      page: _toInt(json['page']),
      limit: _toInt(json['limit']),
      total: _toInt(json['total']),
      totalPages: _toInt(json['totalPages']),
      hasNextPage: _toBool(json['hasNextPage']),
      hasPrevPage: _toBool(json['hasPrevPage']),
    );
  }
}

class DeviceToken {
  final int? idDeviceToken;
  final int idUsuario;
  final String token;
  final String plataforma;
  final bool activo;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  DeviceToken({
    this.idDeviceToken,
    required this.idUsuario,
    required this.token,
    required this.plataforma,
    required this.activo,
    this.createdAt,
    this.updatedAt,
  });

  factory DeviceToken.fromJson(Map<String, dynamic> json) {
    int _toInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return DeviceToken(
      idDeviceToken: json['id_device_token'] != null ? _toInt(json['id_device_token']) : null,
      idUsuario: _toInt(json['id_usuario']),
      token: json['token']?.toString() ?? '',
      plataforma: json['plataforma']?.toString() ?? '',
      activo: json['activo'] == true || json['activo'] == 'true' || json['activo'] == 1,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'plataforma': plataforma,
    };
  }
}