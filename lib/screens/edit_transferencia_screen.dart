// lib/screens/edit_transferencia_screen.dart
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import 'dart:convert';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import '../services/ocr_service.dart';

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
  late OCRService _ocrService;
  
  final _formKey = GlobalKey<FormState>();
  final _montoController = TextEditingController();
  final _observacionesController = TextEditingController();
  
  List<Map<String, dynamic>> _bancos = [];
  int? _bancoSeleccionadoId;
  String _bancoSeleccionadoNombre = '';
  late DateTime _fechaSeleccionada;
  File? _imagenSeleccionada;
  bool _isLoading = true;
  bool _isLoadingBancos = false;
  bool _isProcessingOCR = false;
  String _errorMessage = '';
  bool _disponibleParaEditar = true;
  String _token = '';

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _ocrService = OCRService();
    _inicializar();
  }

  Future<void> _inicializar() async {
    _token = widget.token;
    if (_token.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('token') ?? '';
    }
    
    if (_token.isEmpty) {
      _showSnack('Error: Sesión expirada', isError: true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.pop(context);
      });
      return;
    }
    
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
      
      if (response['success']) {
        final transferenciaActualizada = response['data'];
        _disponibleParaEditar = transferenciaActualizada['disponible_para_editar'] == true;
        
        if (!_disponibleParaEditar && mounted) {
          _showSnack('No puedes editar esta transferencia. El tiempo para editarla ha expirado.', isError: true);
        }
        
        _montoController.text = transferenciaActualizada['monto']?.toString() ?? '';
        _observacionesController.text = transferenciaActualizada['observaciones'] ?? '';
        _bancoSeleccionadoId = transferenciaActualizada['id_banco'];
        _bancoSeleccionadoNombre = transferenciaActualizada['nombre_banco'] ?? '';
        _fechaSeleccionada = DateTime.tryParse(transferenciaActualizada['fecha_transferencia'] ?? '') ?? DateTime.now();
        
        setState(() {
          _isLoading = false;
        });
        
        await _loadBancos();
      } else {
        _showSnack(response['message'] ?? 'Error al cargar datos', isError: true);
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) print('Error cargando datos actualizados: $e');
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
          
          if (_bancoSeleccionadoId != null) {
            final bancoEncontrado = _bancos.firstWhere(
              (b) => b['id_banco'] == _bancoSeleccionadoId,
              orElse: () => {},
            );
            if (bancoEncontrado.isNotEmpty) {
              setState(() {
                _bancoSeleccionadoNombre = bancoEncontrado['nombre_banco'] ?? '';
              });
            }
          }
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
      if (kDebugMode) print('Error cargando bancos: $e');
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
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Seleccionar Banco', style: TextStyle(color: AppTheme.textPrimary)),
          content: Container(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: _bancos.length,
              itemBuilder: (context, index) {
                final banco = _bancos[index];
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
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

  // ✅ Validar imagen con OCR
  Future<bool> _validarImagenConOCR(File imagen) async {
    setState(() {
      _isProcessingOCR = true;
    });
    
    try {
      final resultado = await _ocrService.validarComprobante(imagen);
      
      if (resultado['success']) {
        if (mounted) {
          _showSnack('✅ ${resultado['mensaje']}');
        }
        return true;
      } else {
        if (mounted) {
          _showSnack(resultado['mensaje'], isError: true);
        }
        return false;
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Error al validar la imagen', isError: true);
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingOCR = false;
        });
      }
    }
  }

  // ✅ Modificado con validación OCR
  Future<void> _seleccionarImagen() async {
    if (!_disponibleParaEditar) {
      _showSnack('No puedes editar esta transferencia. El tiempo ha expirado.', isError: true);
      return;
    }
    
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final imagenTemp = File(pickedFile.path);
      final esValida = await _validarImagenConOCR(imagenTemp);
      
      if (esValida) {
        setState(() {
          _imagenSeleccionada = imagenTemp;
        });
      }
    }
  }

  // ✅ Modificado con validación OCR
  Future<void> _tomarFoto() async {
    if (!_disponibleParaEditar) {
      _showSnack('No puedes editar esta transferencia. El tiempo ha expirado.', isError: true);
      return;
    }
    
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      final imagenTemp = File(pickedFile.path);
      final esValida = await _validarImagenConOCR(imagenTemp);
      
      if (esValida) {
        setState(() {
          _imagenSeleccionada = imagenTemp;
        });
      }
    }
  }

  void _mostrarImagenAmpliada(String url) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: AppTheme.surface,
          child: Container(
            width: double.maxFinite,
            height: 500,
            child: Column(
              children: [
                AppBar(
                  title: const Text('Comprobante'),
                  backgroundColor: AppTheme.green,
                  foregroundColor: Colors.white,
                  automaticallyImplyLeading: false,
                  actions: [
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                Expanded(
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                    errorWidget: (context, url, error) => Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 48, color: AppTheme.error),
                          const SizedBox(height: 16),
                          const Text('No se pudo cargar la imagen', style: TextStyle(color: AppTheme.textSecondary)),
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
    final imagenUrl = ApiService.getImagenUrl(urlComprobante);
    
    if (urlComprobante == null || urlComprobante.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Comprobante actual:',
          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _mostrarImagenAmpliada(imagenUrl),
          child: Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
              image: DecorationImage(
                image: CachedNetworkImageProvider(imagenUrl),
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
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
      if (kDebugMode) print('Error guardando cambios: $e');
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
        backgroundColor: isError ? AppTheme.error : AppTheme.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: const Text('Editar Transferencia', style: TextStyle(color: AppTheme.textPrimary)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isLoadingBancos
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        if (!_disponibleParaEditar)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.errorBg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.error),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.timer_off, size: 16, color: AppTheme.error),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'No puedes editar esta transferencia. El tiempo para editarla ha expirado.',
                                    style: TextStyle(fontSize: 12, color: AppTheme.error),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        
                        if (!_disponibleParaEditar) const SizedBox(height: 16),
                        
                        // Banco
                        InkWell(
                          onTap: _disponibleParaEditar ? _showBancoDialog : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              border: Border.all(color: AppTheme.border),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.account_balance, color: _disponibleParaEditar ? AppTheme.green : AppTheme.textDisabled),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Banco *', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                                      const SizedBox(height: 4),
                                      Text(
                                        _bancoSeleccionadoNombre.isEmpty
                                            ? 'Selecciona un banco'
                                            : _bancoSeleccionadoNombre,
                                        style: TextStyle(
                                          color: _disponibleParaEditar ? AppTheme.textPrimary : AppTheme.textDisabled,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_disponibleParaEditar) Icon(Icons.arrow_drop_down, color: AppTheme.textSecondary),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Monto
                        TextFormField(
                          controller: _montoController,
                          enabled: _disponibleParaEditar,
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
                            if (value == null || value.isEmpty) return 'Ingresa el monto';
                            if (double.tryParse(value) == null) return 'Ingresa un monto válido';
                            if (double.parse(value) <= 0) return 'El monto debe ser mayor a 0';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // Fecha
                        InkWell(
                          onTap: _disponibleParaEditar ? _seleccionarFecha : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              border: Border.all(color: AppTheme.border),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today, color: _disponibleParaEditar ? AppTheme.green : AppTheme.textDisabled),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Fecha de transferencia *', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${_fechaSeleccionada.day}/${_fechaSeleccionada.month}/${_fechaSeleccionada.year}',
                                        style: TextStyle(color: _disponibleParaEditar ? AppTheme.textPrimary : AppTheme.textDisabled),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Imagen actual
                        _buildImagenActual(),
                        
                        // Nueva imagen con OCR
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
                                    Icon(Icons.image, color: _disponibleParaEditar ? AppTheme.green : AppTheme.textDisabled),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Nuevo comprobante (opcional)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        color: _disponibleParaEditar ? AppTheme.textPrimary : AppTheme.textDisabled,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              
                              // ✅ Indicador de procesamiento OCR
                              if (_isProcessingOCR)
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.green),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Validando imagen...',
                                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
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
                              if (_imagenSeleccionada == null && _disponibleParaEditar && !_isProcessingOCR)
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
                          enabled: _disponibleParaEditar,
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
                        
                        // Botón guardar
                        if (_disponibleParaEditar)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _guardarCambios,
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
                                  : const Text('Guardar Cambios', style: TextStyle(fontSize: 16)),
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
    _ocrService.dispose();
    super.dispose();
  }
}