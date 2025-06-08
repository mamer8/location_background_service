

import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class BackgroundLocationService {
  static const String serviceName = "location_tracker";
  
  // URLs - غير الـ BASE_URL حسب الـ backend بتاعك
  static const String BASE_URL = "https://asom.octopusteam.net/api/v1/";
  static const String UPDATE_LOCATION_ENDPOINT = "add-shipment-location";
  
  // Stream للاستماع لتحديثات الموقع من الـ UI
  static StreamController<Map<String, dynamic>> _locationController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  static Stream<Map<String, dynamic>> get onLocationUpdate => 
      _locationController.stream;
  
  /// بدء الخدمة
  static Future<bool> startService() async {
    final service = FlutterBackgroundService();
    bool isRunning = await service.isRunning();
    
    if (!isRunning) {
      return await service.startService();
    }
    return true;
  }
  
  /// إيقاف الخدمة
  static Future<bool> stopService() async {
    final service = FlutterBackgroundService();
    bool isRunning = await service.isRunning();
    
    if (isRunning) {
      service.invoke("stop");
      return true;
    }
    return true;
  }
  
  /// التحقق من حالة الخدمة
  static Future<bool> isServiceRunning() async {
    final service = FlutterBackgroundService();
    return await service.isRunning();
  }
}

/// تهيئة الخدمة
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'location_tracker_channel',
      initialNotificationTitle: 'Location Tracker',
      initialNotificationContent: 'Initializing...',
      foregroundServiceNotificationId: 888,

    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

/// للـ iOS Background
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  SharedPreferences preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  final log = preferences.getStringList('log') ?? <String>[];
  log.add(DateTime.now().toIso8601String());
  await preferences.setStringList('log', log);

  return true;
}

/// نقطة بداية الخدمة
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  
  print("🚀 Background service started");
  
  Timer? timer;
  
  // للـ Android فقط
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
    
    // تحديث الإشعار الأولي
    service.setForegroundNotificationInfo(
      title: "Location Tracker",
      content: "Service started successfully",
    );
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // بدء المؤقت
  timer = Timer.periodic(const Duration(minutes: 2), (timer) async {
    await _performLocationUpdate(service);
  });

  // تنفيذ أول تحديث فوراً
  await _performLocationUpdate(service);

  // الاستماع لأوامر الإيقاف
  service.on('stop').listen((event) {
    print("🛑 Stopping background service");
    timer?.cancel();
    service.stopSelf();
  });
}

/// تنفيذ تحديث الموقع
Future<void> _performLocationUpdate(ServiceInstance service) async {
  try {
    print("📍 Performing location update...");
    
    // تحديث الإشعار
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "Location Tracker",
        content: "Getting location... ${DateTime.now().toString().substring(11, 19)}",
      );
    }
    
    // 1. التحقق من الإذونات
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || 
        permission == LocationPermission.deniedForever) {
      print("❌ Location permission denied");
      _updateNotification(service, "Permission denied", isError: true);
      return;
    }
    
    // 2. التحقق من تفعيل الـ GPS
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print("❌ Location service disabled");
      _updateNotification(service, "GPS disabled", isError: true);
      return;
    }
    
    // 3. الحصول على الموقع
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 30),
      );
      print("📍 Location: ${position.latitude}, ${position.longitude}");
    } catch (e) {
      print("❌ Failed to get location: $e");
      _updateNotification(service, "Failed to get location", isError: true);
      return;
    }
    
    // 4. إرسال للسيرفر
    String token = "Bearer 94|b0ohR4UjPGEpsNpdVAWQcLJSjHFNZSSl5RkPdImE61850af2";
    bool success = await _sendLocationToServer(
      position.latitude, 
      position.longitude, 
      token
    );
    
    String timestamp = DateTime.now().toString().substring(11, 19);
    
    if (success) {
      // حفظ البيانات
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_location_update', timestamp);
      await prefs.setDouble('last_lat', position.latitude);
      await prefs.setDouble('last_lng', position.longitude);
      
      _updateNotification(service, "Updated at $timestamp");
      print("✅ Location updated successfully");
      
      // إرسال للـ UI
      service.invoke('update', {
        'lat': position.latitude,
        'lng': position.longitude,
        'timestamp': timestamp,
        'status': 'success'
      });
      
    } else {
      _updateNotification(service, "Server error at $timestamp", isError: true);
      print("❌ Server error");
      
      service.invoke('update', {
        'timestamp': timestamp,
        'status': 'error',
        'message': 'Server error'
      });
    }
    
  } catch (e, stackTrace) {
    print("❌ Location update failed: $e");
    print("Stack trace: $stackTrace");
    
    _updateNotification(service, "Update failed", isError: true);
    
    // حفظ الخطأ
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_background_error', e.toString());
    await prefs.setString('last_background_error_time', DateTime.now().toIso8601String());
    
    service.invoke('update', {
      'timestamp': DateTime.now().toString().substring(11, 19),
      'status': 'error',
      'message': e.toString()
    });
  }
}

/// تحديث الإشعار
void _updateNotification(ServiceInstance service, String message, {bool isError = false}) {
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: "Location Tracker",
      content: message,
    );
  }
}

/// إرسال الموقع للسيرفر
Future<bool> _sendLocationToServer(double lat, double lng, String token) async {
  try {
    final url = Uri.parse('${BackgroundLocationService.BASE_URL}${BackgroundLocationService.UPDATE_LOCATION_ENDPOINT}');
    
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': token,
      },
      body: jsonEncode({
        "shipment_id": 22,
        "location": "Lat: $lat, Lng: $lng",
        "key": "addShipmentLocation"
      }),
    ).timeout(const Duration(seconds: 30));
    
    print("📡 Server response: ${response.statusCode}");
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      print("✅ Location sent successfully");
      return true;
    } else {
      print("❌ Server error: ${response.statusCode} - ${response.body}");
      return false;
    }
    
  } catch (e) {
    print("❌ Network error: $e");
    return false;
  }
}
