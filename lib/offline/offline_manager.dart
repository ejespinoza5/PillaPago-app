// lib/offline/offline_manager.dart
import '../services/database_service.dart';
import '../services/api_service.dart';

class OfflineManager {
  static final OfflineManager _instance = OfflineManager._internal();
  factory OfflineManager() => _instance;
  OfflineManager._internal();

  final DatabaseService _db = DatabaseService();
  final ApiService _api = ApiService();

  // Guardar datos en caché local
  Future<void> saveDataToCache({
    required Map<String, dynamic> userData,
    required Map<String, dynamic> totalData,
    required List<dynamic> transferencias,
    required String periodo,
  }) async {
    try {
      if (userData.isNotEmpty) {
        await _db.guardarUsuario(userData);
      }
      
      if (totalData.isNotEmpty) {
        await _db.guardarTotal(
          periodo,
          totalData['total'] ?? 0,
          totalData['moneda'] ?? 'USD',
        );
      }
      
      if (transferencias.isNotEmpty) {
        await _db.guardarTransferencias(transferencias);
      }
      
      print('💾 Datos guardados en caché local');
    } catch (e) {
      print('❌ Error guardando datos en caché: $e');
    }
  }

  // Cargar datos desde caché local
  Future<Map<String, dynamic>> loadDataFromCache() async {
    try {
      final usuario = await _db.getUsuarioCache();
      final transferencias = await _db.getTransferenciasCache();
      
      return {
        'usuario': usuario,
        'transferencias': transferencias,
      };
    } catch (e) {
      print('❌ Error cargando datos desde caché: $e');
      return {
        'usuario': null,
        'transferencias': [],
      };
    }
  }

  // Guardar transferencia pendiente (para cuando no hay internet)
  Future<int> saveTransferenciaPendiente({
  required int idBanco,
  required String fechaTransferencia,
  required double monto,
  required String observaciones,
  required String imagenPath,
}) async {
  return await _db.guardarTransferenciaPendiente(
    idBanco: idBanco,
    fechaTransferencia: fechaTransferencia,
    monto: monto,
    observaciones: observaciones,
    imagenPath: imagenPath,
  );
}

  // Limpiar caché viejo
  Future<void> clearOldCache() async {
    await _db.limpiarCacheViejo();
  }

  // Cerrar conexión a la base de datos
  Future<void> close() async {
    await _db.cerrarDatabase();
  }
}