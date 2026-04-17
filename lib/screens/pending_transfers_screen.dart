// lib/screens/pending_transfers_screen.dart
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/connectivity_service.dart';
import '../offline/sync_manager.dart';
import '../theme/app_theme.dart';
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
      _showSnack(result['message'], isError: false);
      await _loadPendingTransfers();
    } else {
      _showSnack(result['message'], isError: true);
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
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Eliminar Transferencia', style: TextStyle(color: AppTheme.textPrimary)),
          content: const Text('¿Estás seguro de que deseas eliminar esta transferencia pendiente?', style: TextStyle(color: AppTheme.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppTheme.error),
              child: Text('Eliminar', style: TextStyle(color: AppTheme.error)),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await _dbService.eliminarTransferenciaPendiente(id);
      await _loadPendingTransfers();
      _showSnack('Transferencia eliminada', isError: false, isWarning: true);
    }
  }

  void _showSnack(String msg, {bool isError = false, bool isWarning = false}) {
    Color bgColor;
    if (isError) {
      bgColor = AppTheme.error;
    } else if (isWarning) {
      bgColor = AppTheme.warning;
    } else {
      bgColor = AppTheme.green;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
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
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: const Text('Transferencias Pendientes', style: TextStyle(color: AppTheme.textPrimary)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_pendientes.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: IconButton(
                icon: Icon(Icons.sync, color: AppTheme.textPrimary),
                onPressed: _isSyncing ? null : _syncNow,
                tooltip: 'Sincronizar ahora',
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadPendingTransfers,
        color: AppTheme.green,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _pendientes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 80,
                          color: AppTheme.green,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No hay transferencias pendientes',
                          style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Las transferencias se sincronizarán automáticamente',
                          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      if (!hasInternet)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          color: AppTheme.warningBg,
                          child: Row(
                            children: [
                              Icon(Icons.wifi_off, color: AppTheme.warning),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Sin conexión a internet. Las transferencias se sincronizarán cuando vuelva la conexión.',
                                  style: TextStyle(color: AppTheme.warning),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _pendientes.length,
                          itemBuilder: (context, index) {
                            final transferencia = _pendientes[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              color: AppTheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: AppTheme.border, width: 0.5),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.pending, color: AppTheme.warning),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Pendiente',
                                              style: TextStyle(
                                                color: AppTheme.warning,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppTheme.warningBg,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            'Intento ${transferencia['intentos']}/5',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.warning,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Monto: ${_formatMonto(transferencia['monto'])}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Fecha: ${_formatFecha(transferencia['fecha_transferencia'])}',
                                      style: TextStyle(color: AppTheme.textSecondary),
                                    ),
                                    if (transferencia['observaciones'] != null &&
                                        transferencia['observaciones'].toString().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          'Obs: ${transferencia['observaciones']}',
                                          style: TextStyle(color: AppTheme.textSecondary),
                                        ),
                                      ),
                                    const SizedBox(height: 8),
                                    Divider(color: AppTheme.border),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () => _eliminarPendiente(transferencia['id']),
                                          icon: Icon(Icons.delete_outline, size: 18, color: AppTheme.error),
                                          label: Text('Eliminar', style: TextStyle(color: AppTheme.error)),
                                          style: TextButton.styleFrom(
                                            foregroundColor: AppTheme.error,
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
                          padding: const EdgeInsets.all(16),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _syncNow,
                              icon: const Icon(Icons.sync),
                              label: Text('Sincronizar Ahora (${_pendientes.length} pendientes)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_isSyncing)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Column(
                              children: [
                                CircularProgressIndicator(color: AppTheme.green),
                                const SizedBox(height: 8),
                                Text('Sincronizando...', style: TextStyle(color: AppTheme.textSecondary)),
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