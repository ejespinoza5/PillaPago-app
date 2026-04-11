// lib/screens/edit_transferencia_screen.dart
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import 'dart:convert';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';


class EditTransferenciaScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic> transferencia;
  final bool puedeEditar;

  const EditTransferenciaScreen({
    Key? key,
    required this.token,
    required this.transferencia,
    required this.puedeEditar,
  }) : super(key: key);

  @override
  _EditTransferenciaScreenState createState() => _EditTransferenciaScreenState();
}

class _EditTransferenciaScreenState extends State<EditTransferenciaScreen> {
  late ApiService _apiService;
  
  final _formKey = GlobalKey<FormState>();
  final _montoController = TextEditingController();
  final _observacionesController = TextEditingController();
  
  List<Map<String, dynamic>> _bancos = [];
  int? _bancoSeleccionadoId;
  String _bancoSeleccionadoNombre = '';
  late DateTime _fechaSeleccionada;
  File? _imagenSeleccionada;
  bool _isLoading = true;  // ✅ Cambiar a true inicialmente
  bool _isLoadingBancos = false;
  String _errorMessage = '';
  bool _disponibleParaEditar = true;
  String _token = '';

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();  // ✅ Inicializar primero
    _inicializar();
  }

  Future<void> _inicializar() async {
    // Obtener token
    _token = widget.token;
    if (_token.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('token') ?? '';
    }
    
    print('=== EDIT TRANSFERENCIA ===');
    print('Token length: ${_token.length}');
    print('ID Transferencia: ${widget.transferencia['id_transferencia']}');
    
    if (_token.isEmpty) {
      _showSnack('Error: Sesión expirada', isError: true);
      Future.delayed(Duration(seconds: 2), () {
        if (mounted) Navigator.pop(context);
      });
      return;
    }
    
    // Cargar datos actualizados desde el backend
    await _cargarDatosActualizados();
  }
  
 Future<void> _cargarDatosActualizados() async {
  setState(() {
    _isLoading = true;
  });
  
  try {
    final response = await _apiService.getTransferenciaById(
      _token,
      widget.transferencia['id_transferencia'],
    );
    
    print('=== RESPUESTA COMPLETA ===');
    print('Response: $response');
    print('Response success: ${response['success']}');
    
    if (response['success']) {
      final transferenciaActualizada = response['data'];
      print('Transferencia actualizada: $transferenciaActualizada');
      print('disponible_para_editar valor: ${transferenciaActualizada['disponible_para_editar']}');
      print('disponible_para_editar tipo: ${transferenciaActualizada['disponible_para_editar'].runtimeType}');
      
      _disponibleParaEditar = transferenciaActualizada['disponible_para_editar'] == true;
      
      print('_disponibleParaEditar asignado: $_disponibleParaEditar');
        
        if (!_disponibleParaEditar && mounted) {
          _showSnack('No puedes editar esta transferencia. El tiempo para editarla ha expirado.', isError: true);
        }
        
        // Cargar datos en los controladores
        _montoController.text = transferenciaActualizada['monto']?.toString() ?? '';
        _observacionesController.text = transferenciaActualizada['observaciones'] ?? '';
        _bancoSeleccionadoId = transferenciaActualizada['id_banco'];
        _bancoSeleccionadoNombre = transferenciaActualizada['banco'] ?? '';
        _fechaSeleccionada = DateTime.tryParse(transferenciaActualizada['fecha_transferencia'] ?? '') ?? DateTime.now();
        
        setState(() {
          _isLoading = false;
        });
        
        // Cargar bancos
        await _loadBancos();
      } else {
        _showSnack(response['message'] ?? 'Error al cargar datos', isError: true);
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error cargando datos actualizados: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadBancos() async {
    setState(() {
      _isLoadingBancos = true;
    });
    
    try {
      final response = await _apiService.getBancos(_token);
      
      if (mounted && response['success']) {
        final data = response['data'];
        if (data is List) {
          setState(() {
            _bancos = List<Map<String, dynamic>>.from(data);
            _isLoadingBancos = false;
          });
        } else {
          setState(() {
            _isLoadingBancos = false;
          });
        }
      } else {
        setState(() {
          _isLoadingBancos = false;
        });
      }
    } catch (e) {
      print('Error cargando bancos: $e');
      setState(() {
        _isLoadingBancos = false;
      });
    }
  }

  void _showBancoDialog() {
    if (!_disponibleParaEditar) {
      _showSnack('No puedes editar esta transferencia. El tiempo ha expirado.', isError: true);
      return;
    }
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Seleccionar Banco'),
          content: Container(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: _bancos.length,
              itemBuilder: (context, index) {
                final banco = _bancos[index];
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _seleccionarFecha() async {
    if (!_disponibleParaEditar) {
      _showSnack('No puedes editar esta transferencia. El tiempo ha expirado.', isError: true);
      return;
    }
    
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
    if (!_disponibleParaEditar) {
      _showSnack('No puedes editar esta transferencia. El tiempo ha expirado.', isError: true);
      return;
    }
    
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _imagenSeleccionada = File(pickedFile.path);
      });
    }
  }

  Future<void> _tomarFoto() async {
    if (!_disponibleParaEditar) {
      _showSnack('No puedes editar esta transferencia. El tiempo ha expirado.', isError: true);
      return;
    }
    
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      setState(() {
        _imagenSeleccionada = File(pickedFile.path);
      });
    }
  }

  void _mostrarImagenAmpliada(String url) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Container(
            width: double.maxFinite,
            height: 500,
            child: Column(
              children: [
                AppBar(
                  title: Text('Comprobante'),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  automaticallyImplyLeading: false,
                  actions: [
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                Expanded(
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => Center(child: CircularProgressIndicator()),
                    errorWidget: (context, url, error) => Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 48, color: Colors.red),
                          SizedBox(height: 16),
                          Text('No se pudo cargar la imagen'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildImagenActual() {
    final String? urlComprobante = widget.transferencia['url_comprobante'];
    
    if (urlComprobante == null || urlComprobante.isEmpty) {
      return SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Comprobante actual:',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        SizedBox(height: 8),
        InkWell(
          onTap: () => _mostrarImagenAmpliada(urlComprobante),
          child: Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
              image: DecorationImage(
                image: CachedNetworkImageProvider(urlComprobante),
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        SizedBox(height: 16),
      ],
    );
  }

  Future<void> _guardarCambios() async {
    if (!_disponibleParaEditar) {
      _showSnack('No puedes editar esta transferencia. El tiempo ha expirado.', isError: true);
      Navigator.pop(context);
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
      final response = await _apiService.editarTransferencia(
        _token,
        widget.transferencia['id_transferencia'],
        idBanco: _bancoSeleccionadoId,
        fechaTransferencia: _fechaSeleccionada.toIso8601String().split('T')[0],
        monto: double.parse(_montoController.text),
        observaciones: _observacionesController.text,
        imagenFile: _imagenSeleccionada,
      );
      
      if (response['success']) {
        _showSnack(response['message']);
        Navigator.pop(context, true);
      } else {
        setState(() {
          _errorMessage = response['message'] ?? 'Error al actualizar';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error guardando cambios: $e');
      setState(() {
        _errorMessage = 'Error de conexión: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Editar Transferencia'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _isLoadingBancos
              ? Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        if (!_disponibleParaEditar)
                          Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.timer_off, color: Colors.red),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'No puedes editar esta transferencia. El tiempo para editarla ha expirado.',
                                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        
                        if (!_disponibleParaEditar) SizedBox(height: 16),
                        
                        // Banco
                        InkWell(
                          onTap: _disponibleParaEditar ? _showBancoDialog : null,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(10),
                              color: _disponibleParaEditar ? Colors.white : Colors.grey.shade50,
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.account_balance, color: _disponibleParaEditar ? Colors.blue : Colors.grey),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Banco *', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                      Text(
                                        _bancoSeleccionadoNombre.isEmpty ? 'Selecciona un banco' : _bancoSeleccionadoNombre,
                                        style: TextStyle(color: _disponibleParaEditar ? Colors.black : Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_disponibleParaEditar) Icon(Icons.arrow_drop_down, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 16),
                        
                        // Monto
                        TextFormField(
                          controller: _montoController,
                          enabled: _disponibleParaEditar,
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Monto *',
                            prefixIcon: Icon(Icons.attach_money),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) return 'Ingresa el monto';
                            if (double.tryParse(value) == null) return 'Ingresa un monto válido';
                            if (double.parse(value) <= 0) return 'El monto debe ser mayor a 0';
                            return null;
                          },
                        ),
                        SizedBox(height: 16),
                        
                        // Fecha
                        InkWell(
                          onTap: _disponibleParaEditar ? _seleccionarFecha : null,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(10),
                              color: _disponibleParaEditar ? Colors.white : Colors.grey.shade50,
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today, color: _disponibleParaEditar ? Colors.blue : Colors.grey),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Fecha de transferencia *', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                      Text(
                                        '${_fechaSeleccionada.day}/${_fechaSeleccionada.month}/${_fechaSeleccionada.year}',
                                        style: TextStyle(color: _disponibleParaEditar ? Colors.black : Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 16),
                        
                        // Imagen actual
                        _buildImagenActual(),
                        
                        // Nueva imagen
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
                                    Icon(Icons.image, color: _disponibleParaEditar ? Colors.blue : Colors.grey),
                                    SizedBox(width: 8),
                                    Text(
                                      'Nuevo comprobante (opcional)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        color: _disponibleParaEditar ? Colors.black : Colors.grey.shade600,
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
                              if (_imagenSeleccionada == null && _disponibleParaEditar)
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
                        
                        // Observaciones
                        TextFormField(
                          controller: _observacionesController,
                          enabled: _disponibleParaEditar,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'Observaciones (opcional)',
                            hintText: 'Ej: Transferencia por venta del día',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            prefixIcon: Icon(Icons.description),
                            alignLabelWithHint: true,
                          ),
                        ),
                        SizedBox(height: 24),
                        
                        // Botón guardar
                        if (_disponibleParaEditar)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _guardarCambios,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isLoading
                                  ? CircularProgressIndicator(color: Colors.white)
                                  : Text('Guardar Cambios', style: TextStyle(fontSize: 16)),
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
    super.dispose();
  }
}