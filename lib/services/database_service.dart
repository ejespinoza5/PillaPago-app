// lib/services/database_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;
  static const String _databaseName = 'pillapago.db';
  static const int _databaseVersion = 2;

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
    print('Creando base de datos local...');
    
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
    
    // Tabla para transferencias pendientes (offline)
    await db.execute('''
      CREATE TABLE transferencias_pendientes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_banco INTEGER,
        fecha_transferencia TEXT,
        monto REAL,
        observaciones TEXT,
        imagen_path TEXT,
        imagen_base64 TEXT,
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
    
    print('Base de datos local creada exitosamente');
  }

  // Agrega el método onUpgrade
Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  print('Actualizando base de datos de versión $oldVersion a $newVersion');
  
  if (oldVersion < 2) {
    // Agregar tabla bancos_cache
    await db.execute('''
      CREATE TABLE bancos_cache (
        id_banco INTEGER PRIMARY KEY,
        nombre_banco TEXT
      )
    ''');
    print('Tabla bancos_cache agregada');
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
    print('✅ Guardadas ${transferencias.length} transferencias en caché');
  }

  Future<List<Map<String, dynamic>>> getTransferenciasCache() async {
    final db = await database;
    final result = await db.query(
      'transferencias_cache',
      orderBy: 'fecha_transferencia DESC',
    );
    print('📀 Cargadas ${result.length} transferencias desde caché');
    return result;
  }

  Future<void> limpiarTransferenciasCache() async {
    final db = await database;
    await db.delete('transferencias_cache');
    print('🗑️ Caché de transferencias limpiado');
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
    print('✅ Guardado total para periodo: $periodo');
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
    print('✅ Usuario guardado en caché');
  }

  // Obtener usuario de caché
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
    String? imagenBase64,
  }) async {
    final db = await database;
    final id = await db.insert('transferencias_pendientes', {
      'id_banco': idBanco,
      'fecha_transferencia': fechaTransferencia,
      'monto': monto,
      'observaciones': observaciones,
      'imagen_path': imagenPath,
      'imagen_base64': imagenBase64,
      'fecha_creacion': DateTime.now().toIso8601String(),
      'intentos': 0,
    });
    print('📝 Transferencia pendiente guardada con ID: $id');
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
    print('✅ Transferencia pendiente eliminada (ID: $id)');
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

  // ==================== LIMPIEZA ====================
  
  Future<void> limpiarCacheViejo() async {
    final db = await database;
    final fechaLimite = DateTime.now().subtract(Duration(days: 7)).toIso8601String();
    final eliminados = await db.delete(
      'transferencias_cache',
      where: 'fecha_sincronizacion < ?',
      whereArgs: [fechaLimite],
    );
    print('🗑️ Eliminadas $eliminados transferencias viejas del caché');
  }

  Future<void> cerrarDatabase() async {
    await _database?.close();
    _database = null;
  }
}