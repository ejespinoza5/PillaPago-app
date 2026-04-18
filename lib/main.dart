import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/registro_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/role_selection_screen.dart';
import 'screens/pending_transfers_screen.dart';
import 'screens/edit_transferencia_screen.dart';
import 'screens/edit_profile_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/change_email_screen.dart';
import 'screens/qr_scanner_screen.dart';
import 'screens/notifications_screen.dart';
import 'services/notification_service.dart';
import 'services/notification_counter_service.dart';
import 'services/database_service.dart';

// Plugin de notificaciones locales
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Handler para notificaciones en segundo plano
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('📱 [BG] Notificación recibida en background');
}

// Mostrar notificación LOCAL cuando la app está en primer plano
Future<void> _showForegroundNotification(RemoteMessage message) async {
  print('🔔 [FOREGROUND] Mostrando notificación local');
  print('🔔 Título: ${message.notification?.title}');
  print('🔔 Cuerpo: ${message.notification?.body}');
  
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'high_importance_channel',
    'Notificaciones Importantes',
    channelDescription: 'Canal para notificaciones importantes de PillaPago',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
    icon: '@drawable/ic_notification',
    color: Color.fromARGB(255, 0, 200, 83),
  );
  
  const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );
  
  const NotificationDetails details = NotificationDetails(
    android: androidDetails,
    iOS: iosDetails,
  );
  
  final title = message.notification?.title ?? 'PillaPago';
  final body = message.notification?.body ?? 'Tienes una nueva notificación';
  
  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch.remainder(100000),
    title,
    body,
    details,
    payload: jsonEncode(message.data),
  );
}

// Mostrar SnackBar cuando la app está abierta (más visible)
void _showForegroundSnackBar(RemoteMessage message) {
  final context = MyApp.navigatorKey.currentContext;
  if (context != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.notification?.title ?? 'Nueva notificación',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (message.notification?.body != null)
              Text(message.notification!.body!),
          ],
        ),
        backgroundColor: AppTheme.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Ver',
          textColor: Colors.white,
          onPressed: () {
            _handleNotificationNavigation(message);
          },
        ),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await _initializeFirebase();
  await _initializeLocalNotifications();
  
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.bgDark,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: Colors.transparent,
  ));
  
  runApp(MyApp());
}

Future<void> _initializeFirebase() async {
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyAjhgbeV727o6MuxcaUgrZog5gUbmcbtNA",
        appId: "1:285182131392:android:412a7c60bed78ce75e4125",
        messagingSenderId: "285182131392",
        projectId: "pillapago",
        storageBucket: "pillapago.firebasestorage.app",
        authDomain: "pillapago.firebaseapp.com",
      ),
    );
    print('✅ Firebase inicializado');
    await _setupFirebaseMessaging();
  } catch (e) {
    print('❌ Error inicializando Firebase: $e');
  }
}

Future<void> _initializeLocalNotifications() async {
  const AndroidNotificationChannel highImportanceChannel = AndroidNotificationChannel(
    'high_importance_channel',
    'Notificaciones Importantes',
    description: 'Canal para notificaciones importantes de PillaPago',
    importance: Importance.high,
  );

  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  
  const DarwinInitializationSettings iosSettings =
      DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  
  const InitializationSettings settings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );
  
  await flutterLocalNotificationsPlugin.initialize(
    settings,
    onDidReceiveNotificationResponse: _onNotificationTapResponse,
  );

  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  await androidPlugin?.createNotificationChannel(highImportanceChannel);
  print('✅ Canal de notificaciones creado');
}

Future<void> _setupFirebaseMessaging() async {
  final settings = await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    provisional: false,
  );
  
  print('📱 Permiso de notificación: ${settings.authorizationStatus}');
  
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  final token = await FirebaseMessaging.instance.getToken();
  print('📱 FCM Token: $token');
  
  if (token != null && token.isNotEmpty) {
    await _updateDeviceToken(token);
  }
  
  FirebaseMessaging.instance.onTokenRefresh.listen((String newToken) async {
    print('📱 Token refrescado: $newToken');
    await _updateDeviceToken(newToken);
  });
  
  // ✅ Notificaciones cuando la app está en primer plano
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('🔔🔔🔔 NOTIFICACIÓN RECIBIDA CON APP ABIERTA 🔔🔔🔔');
    print('📱 Título: ${message.notification?.title}');
    print('📱 Cuerpo: ${message.notification?.body}');
    print('📱 Data: ${message.data}');
    
    // Mostrar notificación local
    _showForegroundNotification(message);
    
    // Mostrar SnackBar
    _showForegroundSnackBar(message);
    
    // Actualizar contador
    _updateNotificationCount(message);
  });
  
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('📱 App abierta desde notificación');
    _handleNotificationNavigation(message);
  });
  
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    print('📱 App abierta desde notificación (cerrada)');
    Future.delayed(const Duration(seconds: 1), () {
      _handleNotificationNavigation(initialMessage);
    });
  }
}

Future<void> _updateNotificationCount(RemoteMessage message) async {
  try {
    await NotificationCounterService.incrementCounter();
    
    final dbService = DatabaseService();
    final notificationData = {
      'id_notificacion': DateTime.now().millisecondsSinceEpoch,
      'tipo': message.data['tipo'] ?? 'general',
      'titulo': message.notification?.title ?? 'Nueva notificación',
      'mensaje': message.notification?.body ?? '',
      'leida': false,
      'created_at': DateTime.now().toIso8601String(),
      'actor_nombre': null,
    };
    await dbService.guardarNotificaciones([notificationData]);
    
  } catch (e) {
    print('Error actualizando contador: $e');
  }
}

Future<void> _updateDeviceToken(String fcmToken) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final userToken = prefs.getString('token');
    
    if (userToken != null && userToken.isNotEmpty) {
      final notificationService = NotificationService(token: userToken);
      await notificationService.registrarDeviceToken(fcmToken, 'android');
      await prefs.setString('fcm_token', fcmToken);
      print('✅ Token registrado en backend');
    } else {
      print('⚠️ No hay sesión iniciada, token no registrado');
    }
  } catch (e) {
    print('❌ Error registrando token: $e');
  }
}

void _onNotificationTapResponse(NotificationResponse response) {
  if (response.payload != null) {
    final data = jsonDecode(response.payload!);
    _navigateToNotifications(data);
  }
}

void _handleNotificationNavigation(RemoteMessage message) {
  _navigateToNotifications(message.data);
}

void _navigateToNotifications(Map<String, dynamic> data) {
  final navigatorState = MyApp.navigatorKey.currentState;
  if (navigatorState != null && navigatorState.context != null) {
    SharedPreferences.getInstance().then((prefs) {
      final token = prefs.getString('token') ?? '';
      if (token.isNotEmpty) {
        navigatorState.pushNamed('/notifications', arguments: token);
      }
    });
  }
}

class MyApp extends StatelessWidget {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'PillaPago',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppTheme.bgDark,
        primaryColor: AppTheme.green,
        colorScheme: const ColorScheme.dark(
          primary: AppTheme.green,
          secondary: AppTheme.greenLight,
          surface: AppTheme.surface,
          error: AppTheme.error,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: AppTheme.textPrimary,
            shadowColor: Colors.transparent,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: AppTheme.buttonText,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppTheme.surface,
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
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppTheme.error),
          ),
          labelStyle: const TextStyle(color: AppTheme.textSecondary),
          hintStyle: const TextStyle(color: AppTheme.textSecondary),
          prefixIconColor: AppTheme.green,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        ),
        textTheme: const TextTheme(
          displayLarge: AppTheme.headline1,
          displayMedium: AppTheme.headline2,
          displaySmall: AppTheme.headline3,
          bodyLarge: AppTheme.body1,
          bodyMedium: AppTheme.body2,
          bodySmall: AppTheme.caption,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: AppTheme.textPrimary),
          titleTextStyle: AppTheme.headline3,
        ),
        cardTheme: CardThemeData(
          color: AppTheme.surface,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          titleTextStyle: AppTheme.headline3.copyWith(color: AppTheme.textPrimary),
          contentTextStyle: AppTheme.body2,
        ),
      ),
      initialRoute: "/",
      routes: {
        "/": (context) => SplashScreen(),
        "/login": (context) => const LoginScreen(),
        "/registro": (context) => const RegistroScreen(),
        "/recuperar-contraseña": (context) => ForgotPasswordScreen(),
      },
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(builder: (_) => const SplashScreen());
          case '/login':
            return MaterialPageRoute(builder: (_) => const LoginScreen());
          case '/registro':
            return MaterialPageRoute(builder: (_) => const RegistroScreen());
          case '/recuperar-contraseña':
            return MaterialPageRoute(builder: (_) => ForgotPasswordScreen());
          case '/role-selection':
            final token = settings.arguments as String? ?? '';
            return MaterialPageRoute(builder: (_) => RoleSelectionScreen(token: token));
          case '/home':
            final token = settings.arguments as String? ?? '';
            return MaterialPageRoute(builder: (_) => HomeScreen(token: token));
          case '/settings':
            final token = settings.arguments as String? ?? '';
            return MaterialPageRoute(builder: (_) => SettingsScreen(token: token));
          case '/notifications':
            final token = settings.arguments as String? ?? '';
            return MaterialPageRoute(builder: (_) => NotificationsScreen(token: token));
          case '/pending-transfers':
            final token = settings.arguments as String? ?? '';
            return MaterialPageRoute(builder: (_) => PendingTransfersScreen(token: token));
          case '/edit-transferencia':
            final args = settings.arguments as Map<String, dynamic>?;
            return MaterialPageRoute(
              builder: (_) => EditTransferenciaScreen(
                token: args?['token'] ?? '',
                transferencia: args?['transferencia'] ?? {},
                puedeEditar: args?['puedeEditar'] ?? false,
              ),
            );
          case '/edit-profile':
            final args = settings.arguments as Map<String, dynamic>?;
            return MaterialPageRoute(
              builder: (_) => EditProfileScreen(
                token: args?['token'] ?? '',
                userData: args?['userData'] ?? {},
              ),
            );
          case '/change-password':
            final token = settings.arguments as String? ?? '';
            return MaterialPageRoute(builder: (_) => ChangePasswordScreen(token: token));
          case '/change-email':
            final args = settings.arguments as Map<String, dynamic>?;
            return MaterialPageRoute(
              builder: (_) => ChangeEmailScreen(
                token: args?['token'] ?? '',
                currentEmail: args?['currentEmail'] ?? '',
              ),
            );
          case '/qr-scanner':
            return MaterialPageRoute(builder: (_) => const QrScannerScreen());
          default:
            return MaterialPageRoute(builder: (_) => const SplashScreen());
        }
      },
    );
  }
}