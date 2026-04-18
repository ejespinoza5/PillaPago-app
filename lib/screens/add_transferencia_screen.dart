// lib/screens/add_transferencia_screen.dart
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import '../services/api_service.dart';
import '../services/connectivity_service.dart';
import '../offline/offline_manager.dart';
import '../services/database_service.dart';
import '../services/ocr_service.dart';  // �S& Agregar import
import '../theme/app_theme.dart';
import 'package:flutter/foundation.dart';

class AddTransferenciaScreen extends StatefulWidget {
  final String token;

  const AddTransferenciaScreen({Key? key, required this.token}) : super(key: key);

  @override
  _AddTransferenciaScreenState createState() => _AddTransferenciaScreenState();
}

class _AddTransferenciaScreenState extends State<AddTransferenciaScreen> {
  late ApiService _apiService;
  late ConnectivityService _connectivityService;
  late DatabaseService _dbService;
  late OCRService _ocrService;  // �S& Servicio OCR
  
  final _formKey = GlobalKey<FormState>();
  final _montoController = TextEditingController();
  final _observacionesController = TextEditingController();
  final _bancoSearchController = TextEditingController();
  
  List<Map<String, dynamic>> _bancos = [];
  List<Map<String, dynamic>> _bancosFiltrados = [];
  int? _bancoSeleccionadoId;
  String _bancoSeleccionadoNombre = '';
  DateTime _fechaSeleccionada = DateTime.now();
  File? _imagenSeleccionada;
  bool _isLoading = false;
  bool _isLoadingBancos = true;
  bool _isProcessingOCR = false;  // �S& Para mostrar loading del OCR
  String _errorMessage = '';

  @override
void initState() {
  super.initState();
  _apiService = ApiService();
  _connectivityService = ConnectivityService();
  _dbService = DatabaseService();
  _ocrService = OCRService();  // �S& Sin errores
  _loadBancos();
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

  // �S& Procesar imagen con OCR
  Future<void> _procesarImagenOCR(File imagen) async {
  setState(() {
    _isProcessingOCR = true;
  });
  
  try {
    final resultado = await _ocrService.validarComprobante(imagen);
    
    if (resultado['success']) {
      // �S& Comprobante válido
      if (kDebugMode) print('�S& ${resultado['mensaje']}');
      _showSnack('�S& Comprobante válido');
    } else {
      // �R Comprobante inválido - rechazar imagen
      setState(() {
        _imagenSeleccionada = null;
      });
      _showSnack(resultado['mensaje'], isError: true);
    }
  } catch (e) {
    setState(() {
      _imagenSeleccionada = null;
    });
    _showSnack('Error al procesar la imagen', isError: true);
  } finally {
    setState(() {
      _isProcessingOCR = false;
    });
  }
}
  
  // �S& Mostrar diálogo con información detectada
  void _mostrarDialogoOCR(Map<String, dynamic> resultado) {
    final items = <Widget>[];
    
    if (resultado['monto'] != null) {
      items.add(_buildInfoRow('�x� Monto:', '\$${resultado['monto']}'));
    }
    if (resultado['fecha'] != null) {
      items.add(_buildInfoRow('�x& Fecha:', resultado['fecha']));
    }
    if (resultado['banco'] != null) {
      items.add(_buildInfoRow('�x�� Banco:', resultado['banco']));
    }
    
    if (items.isEmpty) {
      _showSnack('No se detectó información relevante en la imagen', isError: false);
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Información detectada', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...items,
            const SizedBox(height: 12),
            const Divider(color: AppTheme.border),
            const SizedBox(height: 8),
            const Text(
              '¿Deseas usar esta información para auto-completar el formulario?',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ignorar', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              // Auto-llenar los campos
              setState(() {
                if (resultado['monto'] != null) {
                  _montoController.text = resultado['monto'].toString();
                }
                if (resultado['fecha'] != null) {
                  _autoCompletarFecha(resultado['fecha']);
                }
                if (resultado['banco'] != null) {
                  _autoSeleccionarBanco(resultado['banco']);
                }
              });
              Navigator.pop(context);
              _showSnack('�S& Información auto-completada');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          const SizedBox(width: 8),
          Text(value, style: const TextStyle(color: AppTheme.green)),
        ],
      ),
    );
  }
  
  // �S& Auto-completar fecha desde OCR
  void _autoCompletarFecha(String fechaStr) {
    // Formatos posibles: DD/MM/YYYY, DD-MM-YYYY, YYYY-MM-DD
    DateTime? fecha;
    
    // Formato DD/MM/YYYY
    if (fechaStr.contains('/')) {
      final partes = fechaStr.split('/');
      if (partes.length == 3) {
        fecha = DateTime.tryParse('${partes[2]}-${partes[1]}-${partes[0]}');
      }
    }
    // Formato DD-MM-YYYY
    else if (fechaStr.contains('-')) {
      final partes = fechaStr.split('-');
      if (partes.length == 3) {
        // Si el año es el primero (YYYY-MM-DD)
        if (partes[0].length == 4) {
          fecha = DateTime.tryParse(fechaStr);
        } 
        // Si el día es el primero (DD-MM-YYYY)
        else {
          fecha = DateTime.tryParse('${partes[2]}-${partes[1]}-${partes[0]}');
        }
      }
    }
    
    if (fecha != null && fecha.isBefore(DateTime.now())) {
      _fechaSeleccionada = fecha;
    }
  }
  
  // �S& Auto-seleccionar banco detectado por OCR
  void _autoSeleccionarBanco(String nombreBanco) async {
    // Esperar a que los bancos estén cargados
    if (_bancos.isEmpty) {
      await _loadBancos();
    }
    
    final nombreLower = nombreBanco.toLowerCase();
    final bancoEncontrado = _bancos.firstWhere(
      (b) => b['nombre_banco'].toString().toLowerCase().contains(nombreLower),
      orElse: () => {},
    );
    
    if (bancoEncontrado.isNotEmpty) {
      setState(() {
        _bancoSeleccionadoId = bancoEncontrado['id_banco'];
        _bancoSeleccionadoNombre = bancoEncontrado['nombre_banco'];
      });
      _showSnack('�S& Banco detectado: ${bancoEncontrado['nombre_banco']}');
    }
  }

  Future<void> _loadBancos() async {
    setState(() {
      _isLoadingBancos = true;
      _errorMessage = '';
    });
    
    final hasInternet = await _connectivityService.hasInternet();
    
    if (hasInternet) {
      try {
        final response = await _apiService.getBancos(widget.token);
        
        if (kDebugMode) print('Respuesta de bancos: $response');
        
        if (mounted && response['success']) {
          final data = response['data'];
          
          if (data is List) {
            setState(() {
              _bancos = List<Map<String, dynamic>>.from(data);
              _bancosFiltrados = List<Map<String, dynamic>>.from(data);
              _isLoadingBancos = false;
            });
            
            await _guardarBancosEnCache(_bancos);
            if (kDebugMode) print('Bancos cargados: ${_bancos.length}');
          } else {
            setState(() {
              _errorMessage = 'Formato de datos incorrecto';
              _isLoadingBancos = false;
            });
          }
        } else {
          setState(() {
            _errorMessage = response['message'] ?? 'Error al cargar bancos';
            _isLoadingBancos = false;
          });
        }
      } catch (e) {
        if (kDebugMode) print('Error cargando bancos: $e');
        await _cargarBancosDesdeCache();
      }
    } else {
      await _cargarBancosDesdeCache();
    }
  }
  
  Future<void> _guardarBancosEnCache(List<Map<String, dynamic>> bancos) async {
    final db = await _dbService.database;
    await db.delete('bancos_cache');
    for (var banco in bancos) {
      await db.insert('bancos_cache', {
        'id_banco': banco['id_banco'],
        'nombre_banco': banco['nombre_banco'],
      });
    }
    if (kDebugMode) print('�S& Bancos guardados en caché: ${bancos.length}');
  }
  
  Future<void> _cargarBancosDesdeCache() async {
    try {
      final db = await _dbService.database;
      final result = await db.query('bancos_cache');
      
      if (result.isNotEmpty) {
        setState(() {
          _bancos = List<Map<String, dynamic>>.from(result);
          _bancosFiltrados = List<Map<String, dynamic>>.from(result);
          _isLoadingBancos = false;
        });
        if (kDebugMode) print('�x� Bancos cargados desde caché: ${_bancos.length}');
        
        if (!await _connectivityService.hasInternet()) {
          _showSnack('Modo offline - Mostrando bancos guardados');
        }
      } else {
        setState(() {
          _errorMessage = 'Sin conexión a internet. No hay bancos guardados.';
          _isLoadingBancos = false;
        });
      }
    } catch (e) {
      if (kDebugMode) print('Error cargando bancos desde caché: $e');
      setState(() {
        _errorMessage = 'Error al cargar bancos';
        _isLoadingBancos = false;
      });
    }
  }

  void _filterBancos(String query) {
    setState(() {
      if (query.isEmpty) {
        _bancosFiltrados = List.from(_bancos);
      } else {
        _bancosFiltrados = _bancos.where((banco) {
          return banco['nombre_banco']
              .toString()
              .toLowerCase()
              .contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  void _showBancoDialog() {
    if (_bancos.isEmpty) {
      _showSnack('No hay bancos disponibles. Conéctate a internet para cargarlos.', isError: true);
      return;
    }
    
    _bancoSearchController.clear();
    _filterBancos('');
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: AppTheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text('Seleccionar Banco', style: TextStyle(color: AppTheme.textPrimary)),
              content: Container(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      controller: _bancoSearchController,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Buscar banco...',
                        prefixIcon: Icon(Icons.search, color: AppTheme.green),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.green, width: 2),
                        ),
                      ),
                      onChanged: (value) {
                        setStateDialog(() {
                          if (value.isEmpty) {
                            _bancosFiltrados = List.from(_bancos);
                          } else {
                            _bancosFiltrados = _bancos.where((banco) {
                              return banco['nombre_banco']
                                  .toString()
                                  .toLowerCase()
                                  .contains(value.toLowerCase());
                            }).toList();
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _bancosFiltrados.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.account_balance, size: 48, color: AppTheme.textSecondary),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No se encontraron bancos',
                                    style: TextStyle(color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _bancosFiltrados.length,
                              itemBuilder: (context, index) {
                                final banco = _bancosFiltrados[index];
                                return ListTile(
                                  leading: Icon(Icons.account_balance, color: AppTheme.green),
                                  title: Text(banco['nombre_banco'], style: const TextStyle(color: AppTheme.textPrimary)),
                                  onTap: () {
                                    setState(() {
                                      _bancoSeleccionadoId = banco['id_banco'];
                                      _bancoSeleccionadoNombre = banco['nombre_banco'];
                                    });
                                    Navigator.pop(context);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _seleccionarFecha() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _fechaSeleccionada,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    
    if (picked != null && picked != _fechaSeleccionada) {
      setState(() {
        _fechaSeleccionada = picked;
      });
    }
  }

  // �S& Modificado para procesar OCR después de seleccionar imagen
  Future<void> _seleccionarImagen() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    
    if (pickedFile != null) {
      setState(() {
        _imagenSeleccionada = File(pickedFile.path);
      });
      // �S& Procesar OCR automáticamente
      await _procesarImagenOCR(_imagenSeleccionada!);
    }
  }

  // �S& Modificado para procesar OCR después de tomar foto
  Future<void> _tomarFoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    
    if (pickedFile != null) {
      setState(() {
        _imagenSeleccionada = File(pickedFile.path);
      });
      // �S& Procesar OCR automáticamente
      await _procesarImagenOCR(_imagenSeleccionada!);
    }
  }

  Future<File> _comprimirImagen(File imagen) async {
    final bytes = await imagen.readAsBytes();
    
    if (bytes.length > 500 * 1024) {
      if (kDebugMode) print('�x�️ Imagen grande (${bytes.length} bytes), comprimiendo...');
      
      final picker = ImagePicker();
      final compressedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 50,
      );
      
      if (compressedFile != null) {
        return File(compressedFile.path);
      }
    }
    
    return imagen;
  }

  Future<void> _crearTransferencia() async {
    if (_imagenSeleccionada == null) {
      _showSnack('La imagen del comprobante es obligatoria', isError: true);
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    
    if (_bancoSeleccionadoId == null) {
      _showSnack('Selecciona un banco', isError: true);
      return;
    }
    
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    
    try {
      final hasInternet = await _connectivityService.hasInternet();
      
      if (hasInternet) {
        final response = await _apiService.crearTransferencia(
          widget.token,
          _bancoSeleccionadoId!,
          _fechaSeleccionada.toIso8601String().split('T')[0],
          double.parse(_montoController.text),
          _observacionesController.text,
          _imagenSeleccionada!,
        );
        
        if (response['success']) {
          _showSnack(response['message']);
          Navigator.pop(context, true);
        } else {
          setState(() {
            _errorMessage = response['message'] ?? 'Error al crear transferencia';
            _isLoading = false;
          });
        }
      } else {
        final imagenComprimida = await _comprimirImagen(_imagenSeleccionada!);
        
        final String imagePath = '${(await _dbService.database).path}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await imagenComprimida.copy(imagePath);
        
        await OfflineManager().saveTransferenciaPendiente(
          idBanco: _bancoSeleccionadoId!,
          fechaTransferencia: _fechaSeleccionada.toIso8601String().split('T')[0],
          monto: double.parse(_montoController.text),
          observaciones: _observacionesController.text,
          imagenPath: imagePath,
        );
        
        _showSnack('Transferencia guardada localmente. Se sincronizará cuando haya internet.');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (kDebugMode) print('Error en _crearTransferencia: $e');
      setState(() {
        _errorMessage = 'Error de conexión: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: const Text("Añadir Transferencia", style: TextStyle(color: AppTheme.textPrimary)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoadingBancos
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty && _bancos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: AppTheme.error),
                      const SizedBox(height: 16),
                      Text(_errorMessage, style: const TextStyle(color: AppTheme.error)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadBancos,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.green,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // �S& Indicador de OCR procesando
                        if (_isProcessingOCR)
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Procesando imagen con IA... Detectando información...',
                                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        
                        // Banco
                        InkWell(
                          onTap: _showBancoDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              border: Border.all(color: AppTheme.border),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.account_balance, color: AppTheme.green),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Banco *',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _bancoSeleccionadoNombre.isEmpty
                                            ? 'Selecciona un banco'
                                            : _bancoSeleccionadoNombre,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: _bancoSeleccionadoNombre.isEmpty
                                              ? FontWeight.normal
                                              : FontWeight.w500,
                                          color: _bancoSeleccionadoNombre.isEmpty
                                              ? AppTheme.textSecondary
                                              : AppTheme.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.arrow_drop_down, color: AppTheme.textSecondary),
                              ],
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Monto
                        TextFormField(
                          controller: _montoController,
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: AppTheme.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Monto *',
                            prefixIcon: Icon(Icons.attach_money, color: AppTheme.green),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: AppTheme.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: AppTheme.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: AppTheme.green, width: 2),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Ingresa el monto';
                            }
                            if (double.tryParse(value) == null) {
                              return 'Ingresa un monto válido';
                            }
                            if (double.parse(value) <= 0) {
                              return 'El monto debe ser mayor a 0';
                            }
                            return null;
                          },
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Fecha
                        InkWell(
                          onTap: _seleccionarFecha,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              border: Border.all(color: AppTheme.border),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today, color: AppTheme.green),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Fecha de transferencia *',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${_fechaSeleccionada.day}/${_fechaSeleccionada.month}/${_fechaSeleccionada.year}',
                                        style: const TextStyle(color: AppTheme.textPrimary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Imagen
                        Container(
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            border: Border.all(color: AppTheme.border),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Icon(Icons.image, color: AppTheme.green),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Comprobante *',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      ' (Obligatorio)',
                                      style: TextStyle(
                                        color: AppTheme.error,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_imagenSeleccionada != null) ...[
                                Container(
                                  height: 200,
                                  margin: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    image: DecorationImage(
                                      image: FileImage(_imagenSeleccionada!),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: TextButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        _imagenSeleccionada = null;
                                      });
                                    },
                                    icon: Icon(Icons.delete, color: AppTheme.error),
                                    label: Text('Eliminar imagen', style: TextStyle(color: AppTheme.error)),
                                  ),
                                ),
                              ],
                              if (_imagenSeleccionada == null)
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: _seleccionarImagen,
                                          icon: Icon(Icons.photo_library, color: AppTheme.green),
                                          label: const Text('Galería'),
                                          style: OutlinedButton.styleFrom(
                                            side: BorderSide(color: AppTheme.border),
                                            foregroundColor: AppTheme.textPrimary,
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: _tomarFoto,
                                          icon: Icon(Icons.camera_alt, color: AppTheme.green),
                                          label: const Text('Cámara'),
                                          style: OutlinedButton.styleFrom(
                                            side: BorderSide(color: AppTheme.border),
                                            foregroundColor: AppTheme.textPrimary,
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Observaciones
                        TextFormField(
                          controller: _observacionesController,
                          maxLines: 3,
                          style: const TextStyle(color: AppTheme.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Observaciones (opcional)',
                            hintText: 'Ej: Transferencia por venta del día',
                            prefixIcon: Icon(Icons.description, color: AppTheme.green),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: AppTheme.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: AppTheme.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: AppTheme.green, width: 2),
                            ),
                            alignLabelWithHint: true,
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Botón crear
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _crearTransferencia,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text(
                                    'Crear Transferencia',
                                    style: TextStyle(fontSize: 16),
                                  ),
                          ),
                        ),
                        
                        if (_errorMessage.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.errorBg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.error),
                            ),
                            child: Text(
                              _errorMessage,
                              style: TextStyle(color: AppTheme.error),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
    );
  }

  @override
  void dispose() {
  _montoController.dispose();
  _observacionesController.dispose();
  _bancoSearchController.dispose();
  _ocrService.dispose();  // �S& Limpiar recurso
  super.dispose();
}
}
