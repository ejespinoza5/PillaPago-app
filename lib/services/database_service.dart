// lib/services/database_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;
  static const String _databaseName = 'pillapago.db';
  static const int _databaseVersion = 5;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, _databaseName);
    
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    if (kDebugMode) print('Creando base de datos local...');
    
    // Tabla para transferencias en caché
    await db.execute('''
      CREATE TABLE transferencias_cache (
        id_transferencia TEXT PRIMARY KEY,
        id_negocio INTEGER,
        id_usuario INTEGER,
        usuario_nombre TEXT,
        id_banco INTEGER,
        banco TEXT,
        monto REAL,
        url_comprobante TEXT,
        fecha_transferencia TEXT,
        observaciones TEXT,
        estado TEXT,
        fecha_sincronizacion TEXT
      )
    ''');
    
    // Tabla para totales en caché
    await db.execute('''
      CREATE TABLE totales_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        periodo TEXT UNIQUE,
        total REAL,
        moneda TEXT,
        fecha_actualizacion TEXT
      )
    ''');
    
    // Tabla para usuario en caché
    await db.execute('''
      CREATE TABLE usuario_cache (
        id INTEGER PRIMARY KEY,
        data TEXT,
        fecha_actualizacion TEXT
      )
    ''');
    
    // Tabla para transferencias pendientes
    await db.execute('''
      CREATE TABLE transferencias_pendientes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_banco INTEGER,
        fecha_transferencia TEXT,
        monto REAL,
        observaciones TEXT,
        imagen_path TEXT,
        fecha_creacion TEXT,
        intentos INTEGER DEFAULT 0
      )
    ''');
    
    // Tabla para bancos en caché
    await db.execute('''
      CREATE TABLE bancos_cache (
        id_banco INTEGER PRIMARY KEY,
        nombre_banco TEXT
      )
    ''');
    
    // Tabla para estadísticas en caché
    await db.execute('''
      CREATE TABLE estadisticas_cache (
        id INTEGER PRIMARY KEY,
        data TEXT,
        fecha_actualizacion TEXT
      )
    ''');
    
    // Tabla para notificaciones en caché
    await db.execute('''
      CREATE TABLE notificaciones_cache (
        id_notificacion INTEGER PRIMARY KEY,
        id_destinatario INTEGER,
        id_actor INTEGER,
        id_negocio INTEGER,
        tipo TEXT,
        titulo TEXT,
        mensaje TEXT,
        payload TEXT,
        leida INTEGER DEFAULT 0,
        created_at TEXT,
        actor_nombre TEXT,
        fecha_guardado TEXT
      )
    ''');
    
    // Tabla para acciones pendientes (offline)
    await db.execute('''
      CREATE TABLE acciones_pendientes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tipo TEXT,
        datos TEXT,
        fecha_creacion TEXT,
        sincronizado INTEGER DEFAULT 0
      )
    ''');
    
    // Tabla para contador de notificaciones
    await db.execute('''
      CREATE TABLE contador_notificaciones (
        id INTEGER PRIMARY KEY,
        count INTEGER DEFAULT 0,
        fecha_actualizacion TEXT
      )
    ''');
    
    // Índices para búsquedas rápidas
    await db.execute('''
      CREATE INDEX idx_notificaciones_leida ON notificaciones_cache(leida)
    ''');
    await db.execute('''
      CREATE INDEX idx_notificaciones_fecha ON notificaciones_cache(created_at DESC)
    ''');
    await db.execute('''
      CREATE INDEX idx_acciones_sincronizado ON acciones_pendientes(sincronizado)
    ''');
    
    if (kDebugMode) print('Base de datos local creada exitosamente');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (kDebugMode) print('Actualizando base de datos de versión $oldVersion a $newVersion');
    
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS bancos_cache (
          id_banco INTEGER PRIMARY KEY,
          nombre_banco TEXT
        )
      ''');
      if (kDebugMode) print('✅ Tabla bancos_cache agregada');
    }
    
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS estadisticas_cache (
          id INTEGER PRIMARY KEY,
          data TEXT,
          fecha_actualizacion TEXT
        )
      ''');
      if (kDebugMode) print('✅ Tabla estadisticas_cache agregada');
    }
    
    // Migración a versión 4: eliminar columna imagen_base64
    if (oldVersion < 4) {
      try {
        final result = await db.rawQuery("PRAGMA table_info(transferencias_pendientes)");
        final hasImageBase64 = result.any((col) => col['name'] == 'imagen_base64');
        
        if (hasImageBase64) {
          if (kDebugMode) print('🔄 Migrando tabla transferencias_pendientes...');
          
          await db.execute('''
            CREATE TABLE transferencias_pendientes_temp (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              id_banco INTEGER,
              fecha_transferencia TEXT,
              monto REAL,
              observaciones TEXT,
              imagen_path TEXT,
              fecha_creacion TEXT,
              intentos INTEGER DEFAULT 0
            )
          ''');
          
          await db.rawInsert('''
            INSERT INTO transferencias_pendientes_temp 
            (id, id_banco, fecha_transferencia, monto, observaciones, imagen_path, fecha_creacion, intentos)
            SELECT id, id_banco, fecha_transferencia, monto, observaciones, imagen_path, fecha_creacion, intentos
            FROM transferencias_pendientes
          ''');
          
          await db.execute('DROP TABLE transferencias_pendientes');
          await db.execute('ALTER TABLE transferencias_pendientes_temp RENAME TO transferencias_pendientes');
          if (kDebugMode) print('✅ Tabla transferencias_pendientes migrada correctamente');
        }
      } catch (e) {
        if (kDebugMode) print('Error migrando transferencias_pendientes: $e');
      }
    }
    
    // Migración a versión 5: agregar tablas de notificaciones
    if (oldVersion < 5) {
      // Tabla notificaciones_cache
      await db.execute('''
        CREATE TABLE IF NOT EXISTS notificaciones_cache (
          id_notificacion INTEGER PRIMARY KEY,
          id_destinatario INTEGER,
          id_actor INTEGER,
          id_negocio INTEGER,
          tipo TEXT,
          titulo TEXT,
          mensaje TEXT,
          payload TEXT,
          leida INTEGER DEFAULT 0,
          created_at TEXT,
          actor_nombre TEXT,
          fecha_guardado TEXT
        )
      ''');
      
      // Tabla acciones_pendientes
      await db.execute('''
        CREATE TABLE IF NOT EXISTS acciones_pendientes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tipo TEXT,
          datos TEXT,
          fecha_creacion TEXT,
          sincronizado INTEGER DEFAULT 0
        )
      ''');
      
      // Tabla contador_notificaciones
      await db.execute('''
        CREATE TABLE IF NOT EXISTS contador_notificaciones (
          id INTEGER PRIMARY KEY,
          count INTEGER DEFAULT 0,
          fecha_actualizacion TEXT
        )
      ''');
      
      // Índices
      await db.execute('CREATE INDEX IF NOT EXISTS idx_notificaciones_leida ON notificaciones_cache(leida)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_notificaciones_fecha ON notificaciones_cache(created_at DESC)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_acciones_sincronizado ON acciones_pendientes(sincronizado)');
      
      if (kDebugMode) print('✅ Tablas notificaciones_cache, acciones_pendientes y contador_notificaciones agregadas');
    }
  }

  // ==================== TRANSFERENCIAS CACHE ====================
  
  Future<void> guardarTransferencias(List<dynamic> transferencias) async {
    final db = await database;
    
    for (var transferencia in transferencias) {
      await db.insert(
        'transferencias_cache',
        {
          'id_transferencia': transferencia['id_transferencia'],
          'id_negocio': transferencia['id_negocio'],
          'id_usuario': transferencia['id_usuario'],
          'usuario_nombre': transferencia['usuario_nombre'],
          'id_banco': transferencia['id_banco'],
          'banco': transferencia['banco'],
          'monto': transferencia['monto'],
          'url_comprobante': transferencia['url_comprobante'],
          'fecha_transferencia': transferencia['fecha_transferencia'],
          'observaciones': transferencia['observaciones'],
          'estado': transferencia['estado'],
          'fecha_sincronizacion': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    if (kDebugMode) print('✅ Guardadas ${transferencias.length} transferencias en caché');
  }

  Future<List<Map<String, dynamic>>> getTransferenciasCache() async {
    final db = await database;
    final result = await db.query(
      'transferencias_cache',
      orderBy: 'fecha_transferencia DESC',
    );
    if (kDebugMode) print('📀 Cargadas ${result.length} transferencias desde caché');
    return result;
  }

  Future<void> limpiarTransferenciasCache() async {
    final db = await database;
    await db.delete('transferencias_cache');
    if (kDebugMode) print('🗑️ Caché de transferencias limpiado');
  }

  // ==================== TOTALES CACHE ====================
  
  Future<void> guardarTotal(String periodo, double total, String moneda) async {
    final db = await database;
    await db.insert(
      'totales_cache',
      {
        'periodo': periodo,
        'total': total,
        'moneda': moneda,
        'fecha_actualizacion': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (kDebugMode) print('✅ Guardado total para periodo: $periodo');
  }

  Future<Map<String, dynamic>?> getTotalCache(String periodo) async {
    final db = await database;
    final result = await db.query(
      'totales_cache',
      where: 'periodo = ?',
      whereArgs: [periodo],
    );
    if (result.isNotEmpty) {
      return result.first;
    }
    return null;
  }

  // ==================== USUARIO CACHE ====================
  
  Future<void> guardarUsuario(Map<String, dynamic> usuario) async {
    final db = await database;
    await db.insert(
      'usuario_cache',
      {
        'id': 1,
        'data': jsonEncode(usuario),
        'fecha_actualizacion': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (kDebugMode) print('✅ Usuario guardado en caché');
  }

  Future<Map<String, dynamic>?> getUsuarioCache() async {
    final db = await database;
    final result = await db.query('usuario_cache', where: 'id = ?', whereArgs: [1]);
    if (result.isNotEmpty) {
      final data = result.first['data'];
      if (data is String) {
        return jsonDecode(data);
      }
    }
    return null;
  }

  // ==================== TRANSFERENCIAS PENDIENTES ====================
  
  Future<int> guardarTransferenciaPendiente({
    required int idBanco,
    required String fechaTransferencia,
    required double monto,
    required String observaciones,
    required String imagenPath,
  }) async {
    final db = await database;
    final id = await db.insert('transferencias_pendientes', {
      'id_banco': idBanco,
      'fecha_transferencia': fechaTransferencia,
      'monto': monto,
      'observaciones': observaciones,
      'imagen_path': imagenPath,
      'fecha_creacion': DateTime.now().toIso8601String(),
      'intentos': 0,
    });
    if (kDebugMode) print('📝 Transferencia pendiente guardada con ID: $id');
    return id;
  }

  Future<List<Map<String, dynamic>>> getTransferenciasPendientes() async {
    final db = await database;
    return await db.query(
      'transferencias_pendientes',
      orderBy: 'fecha_creacion ASC',
    );
  }

  Future<void> eliminarTransferenciaPendiente(int id) async {
    final db = await database;
    await db.delete(
      'transferencias_pendientes',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (kDebugMode) print('✅ Transferencia pendiente eliminada (ID: $id)');
  }

  Future<void> actualizarIntentosTransferencia(int id, int intentos) async {
    final db = await database;
    await db.update(
      'transferencias_pendientes',
      {'intentos': intentos},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== NOTIFICACIONES CACHE ====================
  
  /// Guardar lista de notificaciones en caché
  Future<void> guardarNotificaciones(List<dynamic> notificaciones) async {
    final db = await database;
    
    for (var notificacion in notificaciones) {
      await db.insert(
        'notificaciones_cache',
        {
          'id_notificacion': notificacion['id_notificacion'],
          'id_destinatario': notificacion['id_destinatario'],
          'id_actor': notificacion['id_actor'],
          'id_negocio': notificacion['id_negocio'],
          'tipo': notificacion['tipo'],
          'titulo': notificacion['titulo'],
          'mensaje': notificacion['mensaje'],
          'payload': notificacion['payload'] != null ? jsonEncode(notificacion['payload']) : null,
          'leida': notificacion['leida'] == true ? 1 : 0,
          'created_at': notificacion['created_at'],
          'actor_nombre': notificacion['actor_nombre'],
          'fecha_guardado': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    if (kDebugMode) print('✅ Guardadas ${notificaciones.length} notificaciones en caché');
  }
  
  /// Obtener notificaciones desde caché
  Future<List<Map<String, dynamic>>> getNotificacionesCache({
    bool soloNoLeidas = false,
    int page = 1,
    int limit = 20,
  }) async {
    final db = await database;
    
    String where = '';
    List<dynamic> whereArgs = [];
    
    if (soloNoLeidas) {
      where = 'leida = ?';
      whereArgs = [0];
    }
    
    final offset = (page - 1) * limit;
    
    final result = await db.query(
      'notificaciones_cache',
      where: where.isEmpty ? null : where,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    
    if (kDebugMode) print('📀 Cargadas ${result.length} notificaciones desde caché (página $page)');
    return result;
  }
  
  /// Obtener contador de no leídas desde caché
  Future<int> getNotificacionesNoLeidasCountCache() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM notificaciones_cache WHERE leida = 0
    ''');
    return result.first['count'] as int;
  }
  
  /// Marcar notificación como leída en caché
  Future<void> marcarNotificacionLeidaCache(int idNotificacion) async {
    final db = await database;
    await db.update(
      'notificaciones_cache',
      {'leida': 1},
      where: 'id_notificacion = ?',
      whereArgs: [idNotificacion],
    );
    if (kDebugMode) print('✅ Notificación $idNotificacion marcada como leída en caché');
  }
  
  /// Marcar todas las notificaciones como leídas en caché
  Future<int> marcarTodasNotificacionesLeidasCache() async {
    final db = await database;
    final result = await db.update(
      'notificaciones_cache',
      {'leida': 1},
      where: 'leida = 0',
    );
    if (kDebugMode) print('✅ $result notificaciones marcadas como leídas en caché');
    return result;
  }
  
  /// Limpiar notificaciones viejas (más de 30 días)
  Future<void> limpiarNotificacionesViejas() async {
    final db = await database;
    final fechaLimite = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
    final eliminadas = await db.delete(
      'notificaciones_cache',
      where: 'created_at < ?',
      whereArgs: [fechaLimite],
    );
    if (kDebugMode) print('🗑️ Eliminadas $eliminadas notificaciones viejas del caché');
  }

  // ==================== ACCIONES PENDIENTES ====================
  
  /// Guardar acción pendiente para sincronizar después
  Future<int> guardarAccionPendiente(String tipo, Map<String, dynamic> datos) async {
    final db = await database;
    final id = await db.insert('acciones_pendientes', {
      'tipo': tipo,
      'datos': jsonEncode(datos),
      'fecha_creacion': DateTime.now().toIso8601String(),
      'sincronizado': 0,
    });
    if (kDebugMode) print('📝 Acción pendiente guardada: $tipo (ID: $id)');
    return id;
  }
  
  /// Obtener acciones pendientes no sincronizadas
  Future<List<Map<String, dynamic>>> getAccionesPendientes() async {
    final db = await database;
    return await db.query(
      'acciones_pendientes',
      where: 'sincronizado = 0',
      orderBy: 'fecha_creacion ASC',
    );
  }
  
  /// Marcar acción como sincronizada
  Future<void> marcarAccionSincronizada(int id) async {
    final db = await database;
    await db.update(
      'acciones_pendientes',
      {'sincronizado': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (kDebugMode) print('✅ Acción $id marcada como sincronizada');
  }
  
  /// Eliminar acción pendiente
  Future<void> eliminarAccionPendiente(int id) async {
    final db = await database;
    await db.delete(
      'acciones_pendientes',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (kDebugMode) print('🗑️ Acción pendiente $id eliminada');
  }
  
  /// Limpiar acciones pendientes ya sincronizadas (viejas)
  Future<void> limpiarAccionesSincronizadas() async {
    final db = await database;
    final fechaLimite = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
    final eliminadas = await db.delete(
      'acciones_pendientes',
      where: 'sincronizado = 1 AND fecha_creacion < ?',
      whereArgs: [fechaLimite],
    );
    if (kDebugMode) print('🗑️ Eliminadas $eliminadas acciones sincronizadas viejas');
  }

  // ==================== CONTADOR NOTIFICACIONES ====================

  /// Guardar contador de notificaciones en la base de datos local
  Future<void> guardarContadorNotificaciones(int count) async {
    final db = await database;
    await db.insert(
      'contador_notificaciones',
      {
        'id': 1,
        'count': count,
        'fecha_actualizacion': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (kDebugMode) print('✅ Contador de notificaciones guardado: $count');
  }

  /// Obtener contador de notificaciones desde la base de datos local
  Future<int?> getContadorNotificaciones() async {
    final db = await database;
    final result = await db.query(
      'contador_notificaciones',
      where: 'id = ?',
      whereArgs: [1],
    );
    if (result.isNotEmpty) {
      return result.first['count'] as int;
    }
    return null;
  }

  // ==================== LIMPIEZA GENERAL ====================
  
  Future<void> limpiarCacheViejo() async {
    final db = await database;
    final fechaLimite = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
    final eliminados = await db.delete(
      'transferencias_cache',
      where: 'fecha_sincronizacion < ?',
      whereArgs: [fechaLimite],
    );
    if (kDebugMode) print('🗑️ Eliminadas $eliminados transferencias viejas del caché');
    
    // También limpiar notificaciones viejas
    await limpiarNotificacionesViejas();
    
    // Limpiar acciones sincronizadas viejas
    await limpiarAccionesSincronizadas();
  }

  Future<void> cerrarDatabase() async {
    await _database?.close();
    _database = null;
  }
}