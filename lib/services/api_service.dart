import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = "http://192.168.0.4:3000";
  static const String imageBaseUrl = "http://192.168.0.4:3000"; // ✅ URL base para imágenes
  
  //static const String baseUrl = "https://radical-mold-commands-stranger.trycloudflare.com";

  static void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  // ✅ Método helper para obtener URL completa de la imagen
  static String getImagenUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    
    // Si ya es una URL completa (http:// o https://), devolverla
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    
    // Si es una ruta relativa, construir la URL completa
    return '$imageBaseUrl/$url';
  }

  // ==================== TOKEN MANAGEMENT ====================
  
  // Guardar tokens
  static Future<void> saveTokens(String accessToken, String refreshToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', accessToken);
    await prefs.setString('refresh_token', refreshToken);
  }

  // Obtener access token
  static Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  // Obtener refresh token
  static Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('refresh_token');
  }

  // Limpiar tokens
  static Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('refresh_token');
  }

  // Refrescar token
  static Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    try {
      _debugLog('=== refreshToken ===');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );

      _debugLog('refreshToken status: ${response.statusCode}');
      
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        final newAccessToken = data['token'] ?? data['accessToken'];
        final newRefreshToken = data['refreshToken'];
        
        if (newAccessToken != null && newRefreshToken != null) {
          await saveTokens(newAccessToken, newRefreshToken);
        }
        
        return {
          'success': true,
          'token': newAccessToken,
          'refreshToken': newRefreshToken,
        };
      } else {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': data['message'] ?? 'Error al refrescar token',
        };
      }
    } catch (e) {
      _debugLog('refreshToken error: $e');
      return {
        'success': false,
        'message': 'Error de conexión: ${e.toString()}',
      };
    }
  }

// Método para hacer peticiones con manejo automático de refresh token
static Future<Map<String, dynamic>> requestWithAuth(
  String method,
  String endpoint, {
  Map<String, String>? headers,
  Map<String, dynamic>? body,
  bool retry = true,
}) async {
  // Obtener token actualizado cada vez
  String? token = await getAccessToken();

  _debugLog('=== requestWithAuth ===');
  _debugLog('Endpoint: $endpoint');
  
  
  Map<String, String> baseHeaders = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };
  if (headers != null) {
    baseHeaders.addAll(headers);
  }
  
  Future<http.Response> makeRequest() async {
    final url = Uri.parse('$baseUrl$endpoint');
    switch (method.toUpperCase()) {
      case 'GET':
        return await http.get(url, headers: baseHeaders);
      case 'POST':
        return await http.post(url, headers: baseHeaders, body: jsonEncode(body));
      case 'PUT':
        return await http.put(url, headers: baseHeaders, body: jsonEncode(body));
      case 'DELETE':
        return await http.delete(url, headers: baseHeaders);
      case 'PATCH':
        return await http.patch(url, headers: baseHeaders, body: body != null ? jsonEncode(body) : jsonEncode({}));
      default:
        throw Exception('Método no soportado: ${method.toUpperCase()}');
    }
  }
  
  var response = await makeRequest();
  
  // Si el token expiró (401) y tenemos refresh token
  if (response.statusCode == 401 && retry) {
    _debugLog('Token expirado, intentando refrescar...');
    
    final storedRefreshToken = await getRefreshToken();
    if (storedRefreshToken != null) {
      final refreshResponse = await refreshToken(storedRefreshToken);
      if (refreshResponse['success']) {
        _debugLog('Token refrescado exitosamente');
        final newToken = await getAccessToken();
        baseHeaders['Authorization'] = 'Bearer $newToken';
        response = await makeRequest();
      } else {
        await clearTokens();
        return {
          'success': false,
          'unauthorized': true,
          'message': 'Sesión expirada. Por favor inicia sesión nuevamente.',
        };
      }
    } else {
      return {
        'success': false,
        'unauthorized': true,
        'message': 'Sesión expirada. Por favor inicia sesión nuevamente.',
      };
    }
  }
  
  final responseBody = response.body;
  if (responseBody.isEmpty) {
    return {
      'success': false,
      'statusCode': response.statusCode,
      'message': 'El servidor no devolvió una respuesta',
    };
  }
  
  try {
    final data = jsonDecode(responseBody);
    return {
      'success': response.statusCode >= 200 && response.statusCode < 300,
      'statusCode': response.statusCode,
      'data': data,
      'message': data['message'],
    };
  } catch (e) {
    _debugLog('requestWithAuth parse error: $e');
    return {
      'success': false,
      'statusCode': response.statusCode,
      'message': 'Error al procesar respuesta del servidor',
    };
  }
}

  // ==================== AUTH METHODS ====================

  // LOGIN
  static Future login(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/api/auth/email/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(data),
      );
      
      final responseData = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        final accessToken = responseData['token'] ?? responseData['accessToken'];
        final refreshToken = responseData['refreshToken'];
        
        if (accessToken != null && refreshToken != null) {
          await saveTokens(accessToken, refreshToken);
        }
      }
      
      return responseData;
    } catch (e) {
      return {
        'success': false,
        'message': 'Error de conexión: ${e.toString()}',
      };
    }
  }

  // REGISTRO
  static Future register(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse("$baseUrl/api/auth/email/register"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(data),
    );
    return jsonDecode(response.body);
  }

  // REGISTRAR CON IMAGEN
  static Future registerWithImage(Map<String, String> data, File? image) async {
    var request = http.MultipartRequest(
      "POST",
      Uri.parse("$baseUrl/api/auth/email/register"),
    );
    request.fields.addAll(data);
    if (image != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          "foto_perfil",
          image.path,
          contentType: MediaType('image', 'jpeg'),
        ),
      );
    }
    var response = await request.send();
    var res = await http.Response.fromStream(response);
    return jsonDecode(res.body);
  }

  // LOGIN GOOGLE
static Future loginGoogle(String idToken) async {
  try {
    final response = await http.post(
      Uri.parse("$baseUrl/api/auth/google"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"idToken": idToken}),
    );
    
    final data = jsonDecode(response.body);
    
    if (response.statusCode == 409) {
      return {
        'status': 409,
        'statusCode': response.statusCode,
        'success': false,
        'message': data['message'] ?? 'Este correo ya está registrado con email y contraseña',
      };
    }
    
    if (response.statusCode == 200) {
      // Guardar tokens
      final accessToken = data['token'] ?? data['accessToken'];
      final refreshToken = data['refreshToken'];
      
      if (accessToken != null && refreshToken != null) {
        await saveTokens(accessToken, refreshToken);
      }
      
      return {
        'success': true,
        'token': accessToken,
        'refreshToken': refreshToken,
        'usuario': data['usuario'],
        'message': data['message'],
      };
    } else {
      return {
        'success': false,
        'message': data['message'] ?? 'Error al iniciar sesión con Google',
        'statusCode': response.statusCode,
      };
    }
  } catch (e) {
    return {
      'success': false,
      'message': 'Error de conexión: ${e.toString()}',
    };
  }
}

// VERIFICAR CORREO (con token opcional)
static Future<Map<String, dynamic>> verifyEmail(
  String email, 
  String code, {
  String? token,
}) async {
  try {
    final headers = {
      'Content-Type': 'application/json',
    };
    
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/email/verify/confirm'),
      headers: headers,
      body: jsonEncode({'email': email, 'code': code}),
    );
    
    final data = jsonDecode(response.body);
    
    if (response.statusCode == 200) {
      final accessToken = data['token'] ?? data['accessToken'];
      final refreshToken = data['refreshToken'];
      
      if (accessToken != null && refreshToken != null) {
        await saveTokens(accessToken, refreshToken);
      }
      
      return {
        'success': true,
        'message': data['message'] ?? 'Correo verificado exitosamente',
        'token': accessToken,
        'refreshToken': refreshToken,
        'usuario': data['usuario'],
      };
    } else {
      return {
        'success': false,
        'message': data['message'] ?? 'Error al verificar el código',
      };
    }
  } catch (e) {
    return {
      'success': false,
      'message': 'Error de conexión: ${e.toString()}',
    };
  }
}

// REENVIAR CODIGO (con token opcional)
static Future<Map<String, dynamic>> resendVerificationCode(
  String email, {
  String? token,
}) async {
  try {
    final headers = {
      'Content-Type': 'application/json',
    };
    
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/email/verify/request'),
      headers: headers,
      body: jsonEncode({'email': email}),
    );
    
    final data = jsonDecode(response.body);
    
    if (response.statusCode == 200) {
      return {
        'success': true,
        'message': data['message'] ?? 'Código reenviado exitosamente',
      };
    } else {
      return {
        'success': false,
        'message': data['message'] ?? 'Error al reenviar el código',
      };
    }
  } catch (e) {
    return {
      'success': false,
      'message': 'Error de conexión: ${e.toString()}',
    };
  }
}

  // REGISTRAR NEGOCIO (dueño)
  Future<Map<String, dynamic>> registerNegocio(String nombreNegocio, String token) async {
    return await requestWithAuth('POST', '/api/negocios/register-owner', body: {
      'nombre_negocio': nombreNegocio,
    });
  }

  // UNIRSE A NEGOCIO (empleado)
  Future<Map<String, dynamic>> joinNegocio(String codigoInvitacion, String token) async {
    return await requestWithAuth('POST', '/api/negocios/join', body: {
      'codigo_invitacion': codigoInvitacion,
    });
  }

  // OLVIDAR CONTRASEÑA ENVIAR CODIGO
  Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/password/forgot'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200,
        'message': data['message'] ?? 'Código enviado exitosamente',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error de conexión: ${e.toString()}',
      };
    }
  }

  // OLVIDAR CONTRASEÑA CAMBIAR CONTRASEÑA
  Future<Map<String, dynamic>> resetPassword(String email, String code, String newPassword) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/password/reset'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'code': code, 'newPassword': newPassword}),
      );
      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200,
        'message': data['message'] ?? 'Contraseña cambiada exitosamente',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error de conexión: ${e.toString()}',
      };
    }
  }

  // OBTENER USUARIO ACTUAL
  Future<Map<String, dynamic>> getCurrentUser(String token) async {
    return await requestWithAuth('GET', '/api/usuarios/me');
  }

  // ==================== TRANSFERENCIAS ====================

  // Obtener total de hoy
  Future<Map<String, dynamic>> getTotalHoy(String token) async {
    return await requestWithAuth('GET', '/api/transferencias/totales/hoy');
  }

  // Obtener total por día específico
  Future<Map<String, dynamic>> getTotalPorDia(String token, String fecha) async {
    return await requestWithAuth('GET', '/api/transferencias/totales/dia?fecha=$fecha');
  }

  // Obtener total del mes
  Future<Map<String, dynamic>> getTotalMes(String token, int anio, int mes) async {
    return await requestWithAuth('GET', '/api/transferencias/totales/mes?anio=$anio&mes=$mes');
  }

  // Obtener total del año
  Future<Map<String, dynamic>> getTotalAnio(String token, int anio) async {
    return await requestWithAuth('GET', '/api/transferencias/totales/anio?anio=$anio');
  }

// Obtener historial de transferencias
Future<Map<String, dynamic>> getTransferencias(String token, {int page = 1, int limit = 10}) async {
  final response = await requestWithAuth('GET', '/api/transferencias?page=$page&limit=$limit');
  
  if (response['success'] && response['data'] != null) {
    final data = response['data'];
    
    if (data is Map && data.containsKey('data')) {
      return {
        'success': true,
        'data': data['data'],
        'pagination': data['pagination'],
        'totalPages': data['pagination']?['totalPages'] ?? 1,
      };
    } else if (data is List) {
      return {
        'success': true,
        'data': data,
        'totalPages': 1,
      };
    }
  }
  
  return response;
}
 // Obtener bancos

Future<Map<String, dynamic>> getBancos(String token) async {
  try {
    String? accessToken = await getAccessToken();
    
    final response = await http.get(
      Uri.parse('$baseUrl/api/bancos'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      
      if (data is List) {
        return {
          'success': true,
          'data': data,
        };
      } else if (data is Map && data.containsKey('data')) {
        final bancos = data['data'];
        if (bancos is List) {
          return {
            'success': true,
            'data': bancos,
          };
        }
      }
      
      return {
        'success': true,
        'data': data is List ? data : [],
      };
    } else if (response.statusCode == 401) {
      final storedRefreshToken = await getRefreshToken();
      if (storedRefreshToken != null) {
        final refreshResponse = await refreshToken(storedRefreshToken);
        if (refreshResponse['success']) {
          return await getBancos(token);
        }
      }
      return {
        'success': false,
        'message': 'Sesión expirada. Por favor inicia sesión nuevamente.',
      };
    } else {
      final data = jsonDecode(response.body);
      return {
        'success': false,
        'message': data['message'] ?? 'Error al obtener bancos',
      };
    }
  } catch (e) {
    return {
      'success': false,
      'message': 'Error de conexión: ${e.toString()}',
    };
  }
}
  // Crear transferencia
 Future<Map<String, dynamic>> crearTransferencia(
  String token,
  int idBanco,
  String fechaTransferencia,
  double monto,
  String observaciones,
  File imagenFile,
) async {
  try {
    String? accessToken = await ApiService.getAccessToken();
    
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/transferencias'),
    );
    
    request.headers.addAll({
      'Authorization': 'Bearer $accessToken',
    });
    
    request.fields['id_banco'] = idBanco.toString();
    request.fields['fecha_transferencia'] = fechaTransferencia;
    request.fields['monto'] = monto.toString();
    request.fields['observaciones'] = observaciones;
    
    request.files.add(
      await http.MultipartFile.fromPath(
        'imagen',
        imagenFile.path,
        contentType: MediaType('image', 'jpeg'),
      ),
    );
    
    final response = await request.send();
    final responseBody = await response.stream.bytesToString();
    
    if (responseBody.isEmpty) {
      return {
        'success': false,
        'message': 'El servidor no devolvió una respuesta',
      };
    }
    
    final data = jsonDecode(responseBody);
    
    if (response.statusCode == 201 || response.statusCode == 200) {
      return {
        'success': true,
        'message': data['message'] ?? 'Transferencia creada exitosamente',
        'data': data,
      };
    } else if (response.statusCode == 401) {
      final storedRefreshToken = await getRefreshToken();
      if (storedRefreshToken != null) {
        final refreshResponse = await refreshToken(storedRefreshToken);
        if (refreshResponse['success']) {
          return await crearTransferencia(
            token, idBanco, fechaTransferencia, monto, observaciones, imagenFile
          );
        }
      }
      return {
        'success': false,
        'message': 'Sesión expirada. Por favor inicia sesión nuevamente.',
      };
    } else {
      return {
        'success': false,
        'message': data['message'] ?? 'Error al crear transferencia',
      };
    }
  } catch (e) {
    return {
      'success': false,
      'message': 'Error de conexión: ${e.toString()}',
    };
  }
}
  // ==================== EMPLEADOS ====================

 // Obtener empleados activos con paginación
Future<Map<String, dynamic>> getEmpleados(String token, {int page = 1, int limit = 20}) async {
  final response = await requestWithAuth('GET', '/api/empleados?page=$page&limit=$limit');
  
  if (response['success'] && response['data'] != null) {
    final data = response['data'];
    
    if (data is Map && data.containsKey('data')) {
      return {
        'success': true,
        'data': data['data'],
        'pagination': data['pagination'],
        'totalPages': data['pagination']?['totalPages'] ?? 1,
      };
    } else if (data is List) {
      return {
        'success': true,
        'data': data,
        'totalPages': 1,
      };
    }
  }
  
  return response;
}
// Obtener empleados inactivos con paginación
Future<Map<String, dynamic>> getEmpleadosInactivos(String token, {int page = 1, int limit = 20}) async {
  final response = await requestWithAuth('GET', '/api/empleados/inactivos?page=$page&limit=$limit');
  
  if (response['success'] && response['data'] != null) {
    final data = response['data'];
    
    if (data is Map && data.containsKey('data')) {
      return {
        'success': true,
        'data': data['data'],
        'pagination': data['pagination'],
        'totalPages': data['pagination']?['totalPages'] ?? 1,
      };
    } else if (data is List) {
      return {
        'success': true,
        'data': data,
        'totalPages': 1,
      };
    }
  }
  
  return response;
}
  // Obtener detalle de un empleado
Future<Map<String, dynamic>> getEmpleadoDetalle(String token, int idUsuario) async {
  final response = await requestWithAuth('GET', '/api/empleados/$idUsuario');
  
  if (response['success'] && response['data'] != null) {
    final data = response['data'];
    
    if (data.containsKey('empleado')) {
      return {
        'success': true,
        'empleado': data['empleado'],
      };
    } else {
      return {
        'success': true,
        'empleado': data,
      };
    }
  }
  
  return response;
}

  // Inactivar empleado (DELETE)
  Future<Map<String, dynamic>> inactivarEmpleado(String token, int idUsuario) async {
    return await requestWithAuth('DELETE', '/api/empleados/$idUsuario');
  }

  // Reactivar empleado (PATCH)
  Future<Map<String, dynamic>> reactivarEmpleado(String token, int idUsuario) async {
    return await requestWithAuth('PATCH', '/api/empleados/$idUsuario/reactivar');
  }

// Editar transferencia
Future<Map<String, dynamic>> editarTransferencia(
  String token,
  String idTransferencia, {
  int? idBanco,
  String? fechaTransferencia,
  double? monto,
  String? observaciones,
  File? imagenFile,
}) async {
  try {
    if (token.isEmpty) {
      return {
        'success': false,
        'message': 'Token no válido. Por favor inicia sesión nuevamente.',
      };
    }
    
    if (imagenFile != null) {
      var request = http.MultipartRequest(
        'PATCH',
        Uri.parse('$baseUrl/api/transferencias/$idTransferencia'),
      );
      
      request.headers.addAll({
        'Authorization': 'Bearer $token',
      });
      
      if (idBanco != null) request.fields['id_banco'] = idBanco.toString();
      if (fechaTransferencia != null) request.fields['fecha_transferencia'] = fechaTransferencia;
      if (monto != null) request.fields['monto'] = monto.toString();
      if (observaciones != null) request.fields['observaciones'] = observaciones;
      
      request.files.add(
        await http.MultipartFile.fromPath(
          'imagen',
          imagenFile.path,
          contentType: MediaType('image', 'jpeg'),
        ),
      );
      
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final data = jsonDecode(responseBody);
      
      return {
        'success': response.statusCode == 200,
        'message': data['message'] ?? (response.statusCode == 200 ? 'Transferencia actualizada' : 'Error al actualizar'),
      };
    } else {
      Map<String, dynamic> body = {};
      if (idBanco != null) body['id_banco'] = idBanco;
      if (fechaTransferencia != null) body['fecha_transferencia'] = fechaTransferencia;
      if (monto != null) body['monto'] = monto;
      if (observaciones != null) body['observaciones'] = observaciones;
      
      final response = await http.patch(
        Uri.parse('$baseUrl/api/transferencias/$idTransferencia'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
      
      final data = jsonDecode(response.body);
      
      return {
        'success': response.statusCode == 200,
        'message': data['message'] ?? (response.statusCode == 200 ? 'Transferencia actualizada' : 'Error al actualizar'),
      };
    }
  } catch (e) {
    return {
      'success': false,
      'message': 'Error de conexión: ${e.toString()}',
    };
  }
}
// Eliminar transferencia
Future<Map<String, dynamic>> eliminarTransferencia(String token, String idTransferencia) async {
  try {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/transferencias/$idTransferencia'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    
    final data = jsonDecode(response.body);
    
    if (response.statusCode == 200) {
      return {
        'success': true,
        'message': data['message'] ?? 'Transferencia eliminada',
      };
    } else {
      return {
        'success': false,
        'message': data['message'] ?? 'Error al eliminar transferencia',
      };
    }
  } catch (e) {
    return {
      'success': false,
      'message': 'Error de conexión: ${e.toString()}',
    };
  }
}

// Obtener transferencia por ID
Future<Map<String, dynamic>> getTransferenciaById(String token, String idTransferencia) async {
  try {
    final response = await http.get(
      Uri.parse('$baseUrl/api/transferencias/$idTransferencia'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return {
        'success': true,
        'data': data,
      };
    } else {
      final data = jsonDecode(response.body);
      return {
        'success': false,
        'message': data['message'] ?? 'Error al obtener transferencia',
      };
    }
  } catch (e) {
    return {
      'success': false,
      'message': 'Error de conexión: ${e.toString()}',
    };
  }
}
// Editar perfil (nombre y foto)
Future<Map<String, dynamic>> editarPerfil(
  String token, {
  String? nombre,
  File? fotoPerfil,
}) async {
  try {
    if (token.isEmpty) {
      return {
        'success': false,
        'message': 'Token no válido. Por favor inicia sesión nuevamente.',
      };
    }
    
    if (fotoPerfil != null) {
      var request = http.MultipartRequest(
        'PATCH',
        Uri.parse('$baseUrl/api/usuarios/me/perfil'),
      );
      
      request.headers.addAll({
        'Authorization': 'Bearer $token',
      });
      
      if (nombre != null && nombre.isNotEmpty) {
        request.fields['nombre'] = nombre;
      }
      
      request.files.add(
        await http.MultipartFile.fromPath(
          'foto_perfil',
          fotoPerfil.path,
          contentType: MediaType('image', 'jpeg'),
        ),
      );
      
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody);
        return {
          'success': true,
          'message': data['message'] ?? 'Perfil actualizado',
          'data': data,
        };
      } else if (response.statusCode == 401) {
        final storedRefreshToken = await getRefreshToken();
        if (storedRefreshToken != null) {
          final refreshResponse = await refreshToken(storedRefreshToken);
          if (refreshResponse['success']) {
            final newToken = refreshResponse['token'];
            return await editarPerfil(newToken, nombre: nombre, fotoPerfil: fotoPerfil);
          }
        }
        return {
          'success': false,
          'message': 'Sesión expirada. Por favor inicia sesión nuevamente.',
        };
      } else {
        final data = jsonDecode(responseBody);
        return {
          'success': false,
          'message': data['message'] ?? 'Error al actualizar perfil',
        };
      }
    } else {
      Map<String, dynamic> body = {};
      if (nombre != null && nombre.isNotEmpty) {
        body['nombre'] = nombre;
      }
      
      final response = await http.patch(
        Uri.parse('$baseUrl/api/usuarios/me/perfil'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'message': data['message'] ?? 'Perfil actualizado',
          'data': data,
        };
      } else if (response.statusCode == 401) {
        final storedRefreshToken = await getRefreshToken();
        if (storedRefreshToken != null) {
          final refreshResponse = await refreshToken(storedRefreshToken);
          if (refreshResponse['success']) {
            final newToken = refreshResponse['token'];
            return await editarPerfil(newToken, nombre: nombre);
          }
        }
        return {
          'success': false,
          'message': 'Sesión expirada. Por favor inicia sesión nuevamente.',
        };
      } else {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': data['message'] ?? 'Error al actualizar perfil',
        };
      }
    }
  } catch (e) {
    return {
      'success': false,
      'message': 'Error de conexión: ${e.toString()}',
    };
  }
}
// Salir del negocio (empleados y dueños)
Future<Map<String, dynamic>> salirDelNegocio(String token) async {
  try {
    if (token.isEmpty) {
      return {
        'success': false,
        'message': 'Token no válido. Por favor inicia sesión nuevamente.',
      };
    }
    
    final response = await http.delete(
      Uri.parse('$baseUrl/api/empleados/me/salir-negocio'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return {
        'success': true,
        'message': data['message'] ?? 'Has salido del negocio exitosamente',
      };
    } else if (response.statusCode == 401) {
      final storedRefreshToken = await getRefreshToken();
      if (storedRefreshToken != null) {
        final refreshResponse = await refreshToken(storedRefreshToken);
        if (refreshResponse['success']) {
          final newToken = refreshResponse['token'];
          return await salirDelNegocio(newToken);
        }
      }
      return {
        'success': false,
        'message': 'Sesión expirada. Por favor inicia sesión nuevamente.',
      };
    } else {
      final data = jsonDecode(response.body);
      return {
        'success': false,
        'message': data['message'] ?? 'Error al salir del negocio',
      };
    }
  } catch (e) {
    return {
      'success': false,
      'message': 'Error de conexión: ${e.toString()}',
    };
  }
}
// Cambiar contraseña estando autenticado
Future<Map<String, dynamic>> cambiarPassword(
  String token, {
  required String passwordActual,
  required String passwordNueva,
}) async {
  try {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/auth/password'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'password_actual': passwordActual,
        'password_nueva': passwordNueva,
      }),
    );
    
    final data = jsonDecode(response.body);
    
    if (response.statusCode == 200) {
      return {
        'success': true,
        'message': data['message'] ?? 'Contraseña actualizada correctamente',
      };
    } else if (response.statusCode == 401) {
      final storedRefreshToken = await getRefreshToken();
      if (storedRefreshToken != null) {
        final refreshResponse = await refreshToken(storedRefreshToken);
        if (refreshResponse['success']) {
          final newToken = refreshResponse['token'];
          return await cambiarPassword(
            newToken,
            passwordActual: passwordActual,
            passwordNueva: passwordNueva,
          );
        }
      }
      return {
        'success': false,
        'message': 'Sesión expirada. Por favor inicia sesión nuevamente.',
      };
    } else {
      return {
        'success': false,
        'message': data['message'] ?? 'Error al cambiar la contraseña',
      };
    }
  } catch (e) {
    return {
      'success': false,
      'message': 'Error de conexión: ${e.toString()}',
    };
  }
}
// Solicitar cambio de correo (envía código)
Future<Map<String, dynamic>> solicitarCambioEmail(
  String token, {
  required String newEmail,
}) async {
  try {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/email/change/request'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'new_email': newEmail}),
    );
    
    if (response.body.isEmpty) {
      return {
        'success': false,
        'message': 'El servidor no devolvió una respuesta. Verifica tu conexión.',
      };
    }
    
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Error del servidor. Por favor intenta más tarde.',
      };
    }
    
    if (response.statusCode == 200) {
      return {
        'success': true,
        'message': data['message'] ?? 'Código de verificación enviado',
      };
    } else if (response.statusCode == 401) {
      final storedRefreshToken = await getRefreshToken();
      if (storedRefreshToken != null) {
        final refreshResponse = await refreshToken(storedRefreshToken);
        if (refreshResponse['success']) {
          final newToken = refreshResponse['token'];
          return await solicitarCambioEmail(
            newToken,
            newEmail: newEmail,
          );
        }
      }
      return {
        'success': false,
        'message': 'Sesión expirada. Por favor inicia sesión nuevamente.',
      };
    } else {
      return {
        'success': false,
        'message': data['message'] ?? 'Error al solicitar cambio de correo',
      };
    }
  } catch (e) {
    return {
      'success': false,
      'message': 'Error de conexión: ${e.toString()}',
    };
  }
}

// Confirmar cambio de correo con código
Future<Map<String, dynamic>> confirmarCambioEmail(
  String token, {
  required String newEmail,
  required String code,
}) async {
  try {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/email/change/confirm'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'new_email': newEmail,
        'code': code,
      }),
    );
    
    final data = jsonDecode(response.body);
    
    if (response.statusCode == 200) {
      return {
        'success': true,
        'message': data['message'] ?? 'Correo electrónico actualizado correctamente',
      };
    } else if (response.statusCode == 401) {
      final storedRefreshToken = await getRefreshToken();
      if (storedRefreshToken != null) {
        final refreshResponse = await refreshToken(storedRefreshToken);
        if (refreshResponse['success']) {
          final newToken = refreshResponse['token'];
          return await confirmarCambioEmail(
            newToken,
            newEmail: newEmail,
            code: code,
          );
        }
      }
      return {
        'success': false,
        'message': 'Sesión expirada. Por favor inicia sesión nuevamente.',
      };
    } else {
      return {
        'success': false,
        'message': data['message'] ?? 'Error al confirmar cambio de correo',
      };
    }
  } catch (e) {
    return {
      'success': false,
      'message': 'Error de conexión: ${e.toString()}',
    };
  }
}

// Obtener estadísticas de últimos 7 días
Future<Map<String, dynamic>> getEstadisticasUltimos7Dias(String token) async {
  try {
    final response = await http.get(
      Uri.parse('$baseUrl/api/transferencias/estadisticas/ultimos-7-dias'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    
    if (response.statusCode == 200) {
      return {
        'success': true,
        'data': jsonDecode(response.body),
      };
    } else {
      return {
        'success': false,
        'message': 'Error al obtener estadísticas',
      };
    }
  } catch (e) {
    return {
      'success': false,
      'message': 'Error de conexión: ${e.toString()}',
    };
  }
}

Future<Map<String, dynamic>> getTransferenciasFiltradas(
  String token, {
  Map<String, dynamic>? params,
}) async {
  final queryString = params?.entries
      .map((e) => '${e.key}=${e.value}')
      .join('&') ?? '';
  final endpoint = '/api/transferencias${queryString.isNotEmpty ? '?$queryString' : ''}';
  
  return await requestWithAuth('GET', endpoint);
}

// Método para obtener total por usuario (empleado)
Future<Map<String, dynamic>> getTotalPorUsuario(String token, int idUsuario) async {
  return await requestWithAuth('GET', '/api/transferencias/totales/usuario?id_usuario=$idUsuario');
}

// Total por día y usuario específico
Future<Map<String, dynamic>> getTotalPorDiaYUsuario(String token, String fecha, int idUsuario) async {
  return await requestWithAuth('GET', '/api/transferencias/totales/dia?fecha=$fecha&id_usuario=$idUsuario');
}

// Descargar reporte PDF
Future<Map<String, dynamic>> descargarReportePDF({
  required String token,
  int? dia,
  int? mes,
  int? anio,
}) async {
  try {
    final queryParams = <String, String>{};
    
    if (dia != null) queryParams['dia'] = dia.toString();
    if (mes != null) queryParams['mes'] = mes.toString();
    if (anio != null) queryParams['anio'] = anio.toString();
    
    final queryString = queryParams.entries.map((e) => '${e.key}=${e.value}').join('&');
    final url = '$baseUrl/api/transferencias/reporte/pdf${queryString.isNotEmpty ? '?$queryString' : ''}';
    
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/pdf',
      },
    );
    
    if (response.statusCode == 200) {
      return {
        'success': true,
        'data': response.bodyBytes,
        'contentType': response.headers['content-type'],
      };
    } else {
      try {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'message': error['message'] ?? 'Error al generar reporte',
        };
      } catch (e) {
        return {
          'success': false,
          'message': 'Error ${response.statusCode}: No se pudo generar el reporte',
        };
      }
    }
  } catch (e) {
    return {
      'success': false,
      'message': 'Error de conexión: ${e.toString()}',
    };
  }
}
}