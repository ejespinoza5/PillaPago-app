// lib/screens/reportes_screen.dart
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../services/api_service.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReportesScreen extends StatefulWidget {
  final String token;

  const ReportesScreen({Key? key, required this.token}) : super(key: key);

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  late ApiService _apiService;
  late ConnectivityService _connectivityService;
  bool _isLoading = false;
  String _errorMessage = '';
  bool _isOnline = true;
  
  // Variables para filtros
  String _tipoReporte = 'hoy';
  DateTime _fechaSeleccionada = DateTime.now();

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _connectivityService = ConnectivityService();
    _connectivityService.initialize();
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    final isOnline = await _connectivityService.hasInternet();
    setState(() {
      _isOnline = isOnline;
    });
  }

  Future<void> _generarReporte() async {
    // ✅ Verificar conexión a internet primero
    final hasInternet = await _connectivityService.hasInternet();
    
    if (!hasInternet) {
      setState(() {
        _errorMessage = 'Sin conexión a internet. No es posible generar reportes sin conexión.';
        _isLoading = false;
      });
      
      // Mostrar diálogo informativo
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.wifi_off, color: AppTheme.warning),
              const SizedBox(width: 12),
              const Text('Sin conexión', style: TextStyle(color: AppTheme.textPrimary)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: AppTheme.textSecondary),
              const SizedBox(height: 16),
              const Text(
                'No es posible generar reportes en este momento.',
                style: TextStyle(color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Conéctate a internet para generar reportes en PDF.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido', style: TextStyle(color: AppTheme.green)),
            ),
          ],
        ),
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? widget.token;
      
      if (token.isEmpty) {
        setState(() {
          _errorMessage = 'Sesión expirada. Por favor inicia sesión nuevamente.';
          _isLoading = false;
        });
        return;
      }
      
      Map<String, dynamic> response;
      
      switch (_tipoReporte) {
        case 'hoy':
          final hoy = DateTime.now();
          response = await _apiService.descargarReportePDF(
            token: token,
            dia: hoy.day,
            mes: hoy.month,
            anio: hoy.year,
          );
          break;
          
        case 'dia':
          response = await _apiService.descargarReportePDF(
            token: token,
            dia: _fechaSeleccionada.day,
            mes: _fechaSeleccionada.month,
            anio: _fechaSeleccionada.year,
          );
          break;
          
        case 'mes':
          response = await _apiService.descargarReportePDF(
            token: token,
            mes: _fechaSeleccionada.month,
            anio: _fechaSeleccionada.year,
          );
          break;
          
        case 'anio':
          response = await _apiService.descargarReportePDF(
            token: token,
            anio: _fechaSeleccionada.year,
          );
          break;
          
        default:
          response = await _apiService.descargarReportePDF(token: token);
      }
      
      if (response['success']) {
        final directory = await getApplicationDocumentsDirectory();
        final fileName = 'reporte_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(response['data']);
        
        await OpenFile.open(filePath);
        
        if (mounted) {
          _showSnack('✅ Reporte generado y guardado');
        }
      } else {
        setState(() {
          _errorMessage = response['message'] ?? 'Error al generar reporte';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error de conexión: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppTheme.error : AppTheme.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildOpcionReporte({
    required IconData icon,
    required String titulo,
    required String subtitulo,
    required String tipo,
    VoidCallback? onTap,
  }) {
    final isSelected = _tipoReporte == tipo;
    
    return Card(
      color: isSelected ? AppTheme.green.withOpacity(0.1) : AppTheme.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSelected ? BorderSide(color: AppTheme.green, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap ?? () {
          setState(() {
            _tipoReporte = tipo;
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.green : AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: isSelected ? Colors.white : AppTheme.green, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? AppTheme.green : AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitulo,
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: AppTheme.green),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectorFecha() {
    if (_tipoReporte == 'dia' || _tipoReporte == 'mes' || _tipoReporte == 'anio') {
      return Container(
        margin: const EdgeInsets.only(top: 16),
        child: Card(
          color: AppTheme.surface,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            onTap: _seleccionarFecha,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, color: AppTheme.green),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tipoReporte == 'dia' ? 'Fecha específica' : 
                          _tipoReporte == 'mes' ? 'Mes y año' : 'Año',
                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getFechaTexto(),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.textSecondary),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _seleccionarFecha() async {
    if (_tipoReporte == 'dia') {
      final date = await showDatePicker(
        context: context,
        initialDate: _fechaSeleccionada,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
      );
      if (date != null) {
        setState(() {
          _fechaSeleccionada = date;
        });
      }
    } else if (_tipoReporte == 'mes') {
      final date = await showDatePicker(
        context: context,
        initialDate: _fechaSeleccionada,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
      );
      if (date != null) {
        setState(() {
          _fechaSeleccionada = date;
        });
      }
    } else if (_tipoReporte == 'anio') {
      final year = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Seleccionar año'),
          content: DropdownButton<int>(
            value: _fechaSeleccionada.year,
            isExpanded: true,
            items: List.generate(10, (i) {
              int year = DateTime.now().year - i;
              return DropdownMenuItem(
                value: year,
                child: Text(year.toString()),
              );
            }),
            onChanged: (value) {
              if (value != null) {
                Navigator.pop(context, value);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      );
      if (year != null) {
        setState(() {
          _fechaSeleccionada = DateTime(year);
        });
      }
    }
  }

  String _getFechaTexto() {
    if (_tipoReporte == 'dia') {
      return '${_fechaSeleccionada.day}/${_fechaSeleccionada.month}/${_fechaSeleccionada.year}';
    } else if (_tipoReporte == 'mes') {
      return '${_fechaSeleccionada.month}/${_fechaSeleccionada.year}';
    } else if (_tipoReporte == 'anio') {
      return '${_fechaSeleccionada.year}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: const Text('Generar Reporte', style: TextStyle(color: AppTheme.textPrimary)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: AppTheme.textSecondary),
            onPressed: () {
              _showSnack('Selecciona el período y genera un reporte en PDF', isError: false);
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ Indicador de estado de conexión
                  if (!_isOnline)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.errorBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.error),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.wifi_off, color: AppTheme.error),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Sin conexión a internet. No es posible generar reportes.',
                              style: TextStyle(color: AppTheme.error, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  // Título
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.picture_as_pdf, color: AppTheme.green, size: 32),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Reportes de Transferencias',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Genera reportes en PDF con tus transferencias filtradas',
                                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Opciones de reporte
                  const Text(
                    'Selecciona el período',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  
                  _buildOpcionReporte(
                    icon: Icons.today,
                    titulo: 'Hoy',
                    subtitulo: 'Transferencias del día actual',
                    tipo: 'hoy',
                  ),
                  const SizedBox(height: 8),
                  
                  _buildOpcionReporte(
                    icon: Icons.calendar_today,
                    titulo: 'Día específico',
                    subtitulo: 'Transferencias de una fecha exacta',
                    tipo: 'dia',
                  ),
                  const SizedBox(height: 8),
                  
                  _buildOpcionReporte(
                    icon: Icons.calendar_month,
                    titulo: 'Mes',
                    subtitulo: 'Transferencias de todo un mes',
                    tipo: 'mes',
                  ),
                  const SizedBox(height: 8),
                  
                  _buildOpcionReporte(
                    icon: Icons.date_range,
                    titulo: 'Año',
                    subtitulo: 'Transferencias de todo un año',
                    tipo: 'anio',
                  ),
                  
                  // Selector de fecha (si aplica)
                  _buildSelectorFecha(),
                  
                  const SizedBox(height: 32),
                  
                  // Botón generar reporte (deshabilitado si offline)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isOnline ? _generarReporte : null,
                      icon: const Icon(Icons.download),
                      label: const Text('Generar Reporte PDF', style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  
                  if (_errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.errorBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.error),
                      ),
                      child: Text(
                        _errorMessage,
                        style: TextStyle(color: AppTheme.error),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 24),
                  
                  // Información adicional
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info, color: AppTheme.green, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Los reportes se guardan en tu dispositivo y se abren automáticamente.',
                            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}