// lib/offline/sync_manager.dart
import '../services/database_service.dart';
import '../services/api_service.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class SyncManager {
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;
  SyncManager._internal();

  final DatabaseService _db = DatabaseService();
  final ApiService _api = ApiService();

  bool _isSyncing = false;

  // Sincronizar transferencias pendientes
Future<Map<String, dynamic>> syncPendingTransfers(String token) async {
  if (_isSyncing) {
    return {'success': false, 'message': 'Ya hay una sincronización en curso'};
  }

  _isSyncing = true;
  int sincronizadas = 0;
  int errores = 0;

  try {
    final pendientes = await _db.getTransferenciasPendientes();
    
    if (pendientes.isEmpty) {
      _isSyncing = false;
      return {'success': true, 'message': 'No hay transferencias pendientes', 'sincronizadas': 0};
    }

    if (kDebugMode) print('�x Sincronizando ${pendientes.length} transferencias pendientes...');

    for (var pendiente in pendientes) {
      try {
        // Verificar si la imagen existe
        File imagenFile = File(pendiente['imagen_path']);
        
        if (!await imagenFile.exists()) {
          if (pendiente['imagen_base64'] != null) {
            final bytes = base64Decode(pendiente['imagen_base64']);
            final tempDir = Directory.systemTemp;
            imagenFile = File('${tempDir.path}/temp_${DateTime.now().millisecondsSinceEpoch}.jpg');
            await imagenFile.writeAsBytes(bytes);
          } else {
            throw Exception('Imagen no encontrada');
          }
        }
        
        final response = await _api.crearTransferencia(
          token,
          pendiente['id_banco'],
          pendiente['fecha_transferencia'],
          pendiente['monto'].toDouble(),
          pendiente['observaciones'] ?? '',
          imagenFile,
        );
        
        if (response['success']) {
          await _db.eliminarTransferenciaPendiente(pendiente['id']);
          sincronizadas++;
          if (kDebugMode) print('�S& Transferencia ${pendiente['id']} sincronizada');
        } else {
          int nuevosIntentos = (pendiente['intentos'] ?? 0) + 1;
          await _db.actualizarIntentosTransferencia(pendiente['id'], nuevosIntentos);
          errores++;
          
          if (nuevosIntentos >= 5) {
            if (kDebugMode) print('�R Transferencia ${pendiente['id']} alcanzó máximo de intentos');
          }
        }
      } catch (e) {
        if (kDebugMode) print('�R Error sincronizando transferencia ${pendiente['id']}: $e');
        errores++;
      }
    }
    
    _isSyncing = false;
    return {
      'success': true,
      'message': 'Sincronización completada: $sincronizadas sincronizadas, $errores errores',
      'sincronizadas': sincronizadas,
      'errores': errores,
    };
  } catch (e) {
    _isSyncing = false;
    return {
      'success': false,
      'message': 'Error en sincronización: $e',
      'sincronizadas': sincronizadas,
      'errores': errores,
    };
  }
}

  Future<File> _createTempFile(List<int> bytes) async {
    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/temp_image_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await file.writeAsBytes(bytes);
    return file;
  }

  bool get isSyncing => _isSyncing;
}
