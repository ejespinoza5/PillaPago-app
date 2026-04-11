// lib/screens/pending_transfers_screen.dart
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/connectivity_service.dart';
import '../offline/sync_manager.dart';
import 'dart:io';

class PendingTransfersScreen extends StatefulWidget {
  final String token;

  const PendingTransfersScreen({Key? key, required this.token}) : super(key: key);

  @override
  _PendingTransfersScreenState createState() => _PendingTransfersScreenState();
}

class _PendingTransfersScreenState extends State<PendingTransfersScreen> {
  late DatabaseService _dbService;
  late ConnectivityService _connectivityService;
  late SyncManager _syncManager;
  
  List<Map<String, dynamic>> _pendientes = [];
  bool _isLoading = true;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _dbService = DatabaseService();
    _connectivityService = ConnectivityService();
    _syncManager = SyncManager();
    _loadPendingTransfers();
  }

  Future<void> _loadPendingTransfers() async {
    setState(() {
      _isLoading = true;
    });
    
    _pendientes = await _dbService.getTransferenciasPendientes();
    
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _syncNow() async {
    setState(() {
      _isSyncing = true;
    });
    
    final result = await _syncManager.syncPendingTransfers(widget.token);
    
    if (result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']),
          backgroundColor: Colors.green,
        ),
      );
      await _loadPendingTransfers();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']),
          backgroundColor: Colors.red,
        ),
      );
    }
    
    setState(() {
      _isSyncing = false;
    });
  }

  Future<void> _eliminarPendiente(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Eliminar Transferencia'),
          content: Text('¿Estás seguro de que deseas eliminar esta transferencia pendiente?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await _dbService.eliminarTransferenciaPendiente(id);
      await _loadPendingTransfers();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Transferencia eliminada'), backgroundColor: Colors.orange),
      );
    }
  }

  String _formatMonto(dynamic monto) {
    double valor = 0;
    if (monto is int) {
      valor = monto.toDouble();
    } else if (monto is double) {
      valor = monto;
    } else if (monto is String) {
      valor = double.tryParse(monto) ?? 0;
    }
    return '\$${valor.toStringAsFixed(2)}';
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

  @override
  Widget build(BuildContext context) {
    final hasInternet = _connectivityService.isOnline;

    return Scaffold(
      appBar: AppBar(
        title: Text('Transferencias Pendientes'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          if (_pendientes.isNotEmpty)
            IconButton(
              icon: Icon(Icons.sync),
              onPressed: _isSyncing ? null : _syncNow,
              tooltip: 'Sincronizar ahora',
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadPendingTransfers,
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : _pendientes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 80,
                          color: Colors.green,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No hay transferencias pendientes',
                          style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Las transferencias se sincronizarán automáticamente',
                          style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      if (!hasInternet)
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(12),
                          color: Colors.orange.shade100,
                          child: Row(
                            children: [
                              Icon(Icons.wifi_off, color: Colors.orange),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Sin conexión a internet. Las transferencias se sincronizarán cuando vuelva la conexión.',
                                  style: TextStyle(color: Colors.orange.shade800),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: ListView.builder(
                          padding: EdgeInsets.all(16),
                          itemCount: _pendientes.length,
                          itemBuilder: (context, index) {
                            final transferencia = _pendientes[index];
                            return Card(
                              margin: EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.pending, color: Colors.orange),
                                            SizedBox(width: 8),
                                            Text(
                                              'Pendiente',
                                              style: TextStyle(
                                                color: Colors.orange,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          'Intento ${transferencia['intentos']}/5',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Monto: ${_formatMonto(transferencia['monto'])}',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Fecha: ${_formatFecha(transferencia['fecha_transferencia'])}',
                                      style: TextStyle(color: Colors.grey[600]),
                                    ),
                                    if (transferencia['observaciones'] != null &&
                                        transferencia['observaciones'].toString().isNotEmpty)
                                      Padding(
                                        padding: EdgeInsets.only(top: 4),
                                        child: Text(
                                          'Obs: ${transferencia['observaciones']}',
                                          style: TextStyle(color: Colors.grey[600]),
                                        ),
                                      ),
                                    SizedBox(height: 8),
                                    Divider(),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () => _eliminarPendiente(transferencia['id']),
                                          icon: Icon(Icons.delete_outline, size: 18),
                                          label: Text('Eliminar'),
                                          style: TextButton.styleFrom(
                                            foregroundColor: Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      if (_pendientes.isNotEmpty && hasInternet && !_isSyncing)
                        Padding(
                          padding: EdgeInsets.all(16),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _syncNow,
                              icon: Icon(Icons.sync),
                              label: Text('Sincronizar Ahora (${_pendientes.length} pendientes)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ),
                      if (_isSyncing)
                        Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: Column(
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 8),
                                Text('Sincronizando...'),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}