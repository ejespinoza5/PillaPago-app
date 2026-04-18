// lib/services/fcm_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'notification_service.dart';
import 'package:flutter/foundation.dart';

class FCMService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static String? _currentToken;

  // Registrar token después del login
  static Future<void> registerTokenAfterLogin(String userToken) async {
    try {
      _currentToken = await _fcm.getToken();
      if (_currentToken != null) {
        final notificationService = NotificationService(token: userToken);
        await notificationService.registrarDeviceToken(_currentToken!, 'android');
        if (kDebugMode) print('�S& Token FCM registrado después de login: $_currentToken');
        
        // Guardar localmente
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', _currentToken!);
      }
    } catch (e) {
      if (kDebugMode) print('�R Error registrando token después de login: $e');
    }
  }

  // Desregistrar token al cerrar sesión
  static Future<void> unregisterToken(String userToken) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentToken = prefs.getString('fcm_token');
      
      if (_currentToken != null && _currentToken!.isNotEmpty) {
        final notificationService = NotificationService(token: userToken);
        await notificationService.desactivarDeviceToken(_currentToken!);
        await prefs.remove('fcm_token');
        if (kDebugMode) print('�S& Token FCM desregistrado');
      }
    } catch (e) {
      if (kDebugMode) print('�R Error desregistrando token: $e');
    }
  }

  // Obtener token actual
  static Future<String?> getCurrentToken() async {
    try {
      _currentToken = await _fcm.getToken();
      return _currentToken;
    } catch (e) {
      if (kDebugMode) print('Error obteniendo token FCM: $e');
      return null;
    }
  }
}
