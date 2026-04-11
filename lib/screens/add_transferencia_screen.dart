// lib/screens/add_transferencia_screen.dart
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import '../services/api_service.dart';
import '../services/connectivity_service.dart';
import '../offline/offline_manager.dart';
import '../services/database_service.dart';

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
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _connectivityService = ConnectivityService();
    _dbService = DatabaseService();
    _loadBancos();
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _loadBancos() async {
    setState(() {
      _isLoadingBancos = true;
      _errorMessage = '';
    });
    
    final hasInternet = await _connectivityService.hasInternet();
    
    if (hasInternet) {
      // Con internet: cargar desde API
      try {
        final response = await _apiService.getBancos(widget.token);
        
        print('Respuesta de bancos: $response');
        
        if (mounted && response['success']) {
          final data = response['data'];
          
          if (data is List) {
            setState(() {
              _bancos = List<Map<String, dynamic>>.from(data);
              _bancosFiltrados = List<Map<String, dynamic>>.from(data);
              _isLoadingBancos = false;
            });
            
            // Guardar bancos en caché local
            await _guardarBancosEnCache(_bancos);
            print('Bancos cargados: ${_bancos.length}');
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
        print('Error cargando bancos: $e');
        await _cargarBancosDesdeCache();
      }
    } else {
      // Sin internet: cargar desde caché
      await _cargarBancosDesdeCache();
    }
  }
  
  Future<void> _guardarBancosEnCache(List<Map<String, dynamic>> bancos) async {
    final db = await _dbService.database;
    // Limpiar bancos viejos
    await db.delete('bancos_cache');
    // Guardar nuevos bancos
    for (var banco in bancos) {
      await db.insert('bancos_cache', {
        'id_banco': banco['id_banco'],
        'nombre_banco': banco['nombre_banco'],
      });
    }
    print('✅ Bancos guardados en caché: ${bancos.length}');
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
        print('📀 Bancos cargados desde caché: ${_bancos.length}');
        
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
      print('Error cargando bancos desde caché: $e');
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
              title: Text('Seleccionar Banco'),
              content: Container(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      controller: _bancoSearchController,
                      decoration: InputDecoration(
                        hintText: 'Buscar banco...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
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
                    SizedBox(height: 16),
                    Expanded(
                      child: _bancosFiltrados.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.account_balance, size: 48, color: Colors.grey),
                                  SizedBox(height: 16),
                                  Text(
                                    'No se encontraron bancos',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _bancosFiltrados.length,
                              itemBuilder: (context, index) {
                                final banco = _bancosFiltrados[index];
                                return ListTile(
                                  leading: Icon(Icons.account_balance, color: Colors.blue),
                                  title: Text(banco['nombre_banco']),
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
                  child: Text('Cancelar'),
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

  Future<void> _seleccionarImagen() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    
    if (pickedFile != null) {
      setState(() {
        _imagenSeleccionada = File(pickedFile.path);
      });
    }
  }

  Future<void> _tomarFoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    
    if (pickedFile != null) {
      setState(() {
        _imagenSeleccionada = File(pickedFile.path);
      });
    }
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
        // Sin internet: guardar localmente
        List<int> imageBytes = await _imagenSeleccionada!.readAsBytes();
        String imagenBase64 = base64Encode(imageBytes);
        
        await OfflineManager().saveTransferenciaPendiente(
          idBanco: _bancoSeleccionadoId!,
          fechaTransferencia: _fechaSeleccionada.toIso8601String().split('T')[0],
          monto: double.parse(_montoController.text),
          observaciones: _observacionesController.text,
          imagenPath: _imagenSeleccionada!.path,
          imagenBase64: imagenBase64,
        );
        
        _showSnack('Transferencia guardada localmente. Se sincronizará cuando haya internet.');
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error de conexión: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Añadir Transferencia"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoadingBancos
          ? Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty && _bancos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red),
                      SizedBox(height: 16),
                      Text(_errorMessage),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadBancos,
                        child: Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        InkWell(
                          onTap: _showBancoDialog,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.account_balance, color: Colors.blue),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Banco *',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      SizedBox(height: 4),
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
                                              ? Colors.grey.shade600
                                              : Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.arrow_drop_down, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                        
                        SizedBox(height: 16),
                        
                        TextFormField(
                          controller: _montoController,
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Monto *',
                            prefixIcon: Icon(Icons.attach_money),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
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
                        
                        SizedBox(height: 16),
                        
                        InkWell(
                          onTap: _seleccionarFecha,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today, color: Colors.blue),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Fecha de transferencia *',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        '${_fechaSeleccionada.day}/${_fechaSeleccionada.month}/${_fechaSeleccionada.year}',
                                        style: TextStyle(fontSize: 16),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        SizedBox(height: 16),
                        
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Icon(Icons.image, color: Colors.blue),
                                    SizedBox(width: 8),
                                    Text(
                                      'Comprobante *',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      ' (Obligatorio)',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_imagenSeleccionada != null) ...[
                                Container(
                                  height: 200,
                                  margin: EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    image: DecorationImage(
                                      image: FileImage(_imagenSeleccionada!),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.all(8),
                                  child: TextButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        _imagenSeleccionada = null;
                                      });
                                    },
                                    icon: Icon(Icons.delete, color: Colors.red),
                                    label: Text('Eliminar imagen', style: TextStyle(color: Colors.red)),
                                  ),
                                ),
                              ],
                              if (_imagenSeleccionada == null)
                                Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: _seleccionarImagen,
                                          icon: Icon(Icons.photo_library),
                                          label: Text('Galería'),
                                          style: OutlinedButton.styleFrom(
                                            padding: EdgeInsets.symmetric(vertical: 12),
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: _tomarFoto,
                                          icon: Icon(Icons.camera_alt),
                                          label: Text('Cámara'),
                                          style: OutlinedButton.styleFrom(
                                            padding: EdgeInsets.symmetric(vertical: 12),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        
                        SizedBox(height: 16),
                        
                        TextFormField(
                          controller: _observacionesController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'Observaciones (opcional)',
                            hintText: 'Ej: Transferencia por venta del día',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            prefixIcon: Icon(Icons.description),
                            alignLabelWithHint: true,
                          ),
                        ),
                        
                        SizedBox(height: 24),
                        
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _crearTransferencia,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isLoading
                                ? CircularProgressIndicator(color: Colors.white)
                                : Text(
                                    'Crear Transferencia',
                                    style: TextStyle(fontSize: 16),
                                  ),
                          ),
                        ),
                        
                        if (_errorMessage.isNotEmpty) ...[
                          SizedBox(height: 16),
                          Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Text(
                              _errorMessage,
                              style: TextStyle(color: Colors.red.shade700),
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
    super.dispose();
  }
}