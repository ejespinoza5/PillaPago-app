// lib/services/ocr_service.dart
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

class OCRService {
  final textRecognizer = TextRecognizer();
  
  Future<Map<String, dynamic>> validarComprobante(File imagen) async {
    try {
      if (kDebugMode) print('�x� Validando imagen con ML Kit...');
      
      final inputImage = InputImage.fromFile(imagen);
      final recognizedText = await textRecognizer.processImage(inputImage);
      
      // Unir todo el texto reconocido
      String textoCompleto = '';
      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          textoCompleto += line.text + ' ';
        }
      }
      
      final String textLimpio = textoCompleto.replaceAll(RegExp(r'\s+'), '').trim();
      
      // Verificar si hay texto (letras o números)
      final bool tieneTexto = RegExp(r'[a-zA-Z0-9]').hasMatch(textLimpio) 
                              && textLimpio.length > 5;

      if (kDebugMode) print(tieneTexto ? '�S& Comprobante válido' : '�R No se detectó texto');
      if (kDebugMode) print('�x� Texto detectado: ${textLimpio.length > 50 ? textLimpio.substring(0, 50) : textLimpio}...');
      
      return {
        'success': tieneTexto,
        'mensaje': tieneTexto 
            ? 'Comprobante detectado correctamente' 
            : 'No se detectó un comprobante válido. Asegúrate de que la imagen sea clara.',
      };
    } catch (e) {
      if (kDebugMode) print('�R Error en OCR: $e');
      return {
        'success': false,
        'mensaje': 'Error al procesar la imagen. Intenta con otra foto más clara.',
      };
    }
  }
  
  void dispose() {
    textRecognizer.close();
  }
}
