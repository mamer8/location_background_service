

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // تهيئة الـ Background Service
  await initializeService();
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Location Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: LocationControlScreen(),
    );
  }
}

class LocationControlScreen extends StatefulWidget {
  @override
  _LocationControlScreenState createState() => _LocationControlScreenState();
}

class _LocationControlScreenState extends State<LocationControlScreen> {
  bool _isServiceRunning = false;
  String _statusMessage = "Service stopped";
  String _lastUpdate = "Never";
  
  @override
  void initState() {
    super.initState();
    _checkServiceStatus();
    _listenToServiceUpdates();
  }
  
  /// الاستماع لتحديثات الخدمة
  void _listenToServiceUpdates() {
    BackgroundLocationService.onLocationUpdate.listen((data) {
      setState(() {
        _lastUpdate = data['timestamp'] ?? 'Unknown';
        _statusMessage = _isServiceRunning 
            ? "Service running - Last update: $_lastUpdate" 
            : "Service stopped";
      });
    });
  }
  
  /// التحقق من حالة الخدمة عند بدء التطبيق
  Future<void> _checkServiceStatus() async {
    bool isRunning = await BackgroundLocationService.isServiceRunning();
    setState(() {
      _isServiceRunning = isRunning;
      _statusMessage = isRunning ? "Service running" : "Service stopped";
    });
  }
  
  /// طلب الإذونات المطلوبة
  Future<bool> _requestPermissions() async {
    Map<Permission, PermissionStatus> permissions = await [
      Permission.location,
      Permission.locationAlways,
      Permission.notification,
    ].request();
    
    // التحقق من إذن الموقع
    if (permissions[Permission.location]?.isDenied ?? true) {
      _showPermissionDialog("Location permission is required for this feature to work.");
      return false;
    }
    
    // التحقق من إذن الموقع في الخلفية
    if (permissions[Permission.locationAlways]?.isDenied ?? true) {
      _showPermissionDialog("Background location permission is required for continuous tracking.");
      return false;
    }
    
    // إذن الإشعارات (اختياري)
    if (permissions[Permission.notification]?.isDenied ?? true) {
      print("⚠️ Notification permission denied - Background service may not work properly");
    }
    
    return true;
  }
  
  /// بدء خدمة تتبع الموقع
  Future<void> _startLocationService() async {
    setState(() {
      _statusMessage = "Requesting permissions...";
    });
    
    bool hasPermissions = await _requestPermissions();
    if (!hasPermissions) {
      setState(() {
        _statusMessage = "Permissions required";
      });
      return;
    }
    
    setState(() {
      _statusMessage = "Starting service...";
    });
    
    try {
      bool started = await BackgroundLocationService.startService();
      
      if (started) {
        setState(() {
          _isServiceRunning = true;
          _statusMessage = "Service started - Updates every 2 minutes";
        });
        
        _showSnackBar("Location tracking started successfully!", Colors.green);
      } else {
        setState(() {
          _statusMessage = "Failed to start service";
        });
        _showSnackBar("Failed to start location tracking", Colors.red);
      }
      
    } catch (e) {
      setState(() {
        _statusMessage = "Failed to start service: $e";
      });
      
      _showSnackBar("Failed to start location tracking", Colors.red);
    }
  }
  
  /// إيقاف خدمة تتبع الموقع
  Future<void> _stopLocationService() async {
    setState(() {
      _statusMessage = "Stopping service...";
    });
    
    try {
      bool stopped = await BackgroundLocationService.stopService();
      
      if (stopped) {
        setState(() {
          _isServiceRunning = false;
          _statusMessage = "Service stopped";
          _lastUpdate = "Never";
        });
        
        _showSnackBar("Location tracking stopped", Colors.orange);
      } else {
        setState(() {
          _statusMessage = "Failed to stop service";
        });
        _showSnackBar("Failed to stop location tracking", Colors.red);
      }
      
    } catch (e) {
      setState(() {
        _statusMessage = "Failed to stop service: $e";
      });
      
      _showSnackBar("Failed to stop location tracking", Colors.red);
    }
  }
  
  /// عرض رسالة للمستخدم
  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: Duration(seconds: 3),
      ),
    );
  }
  
  /// عرض dialog للإذونات
  void _showPermissionDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Permission Required"),
          content: Text(message),
          actions: [
            TextButton(
              child: Text("Cancel"),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text("Open Settings"),
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
            ),
          ],
        );
      },
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Location Tracker"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isServiceRunning ? Icons.location_on : Icons.location_off,
              size: 80,
              color: _isServiceRunning ? Colors.green : Colors.grey,
            ),
            
            SizedBox(height: 20),
            
            Text(
              "Location Tracking Service",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            SizedBox(height: 10),
            
            Text(
              _statusMessage,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            
            if (_lastUpdate != "Never") ...[
              SizedBox(height: 10),
              Text(
                "Last Update: $_lastUpdate",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.blue[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
            
            SizedBox(height: 40),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isServiceRunning ? _stopLocationService : _startLocationService,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isServiceRunning ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  _isServiceRunning ? "Stop Tracking" : "Start Tracking",
                  style: TextStyle(
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            
            SizedBox(height: 20),
            
            if (_isServiceRunning)
              Container(
                padding: EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  children: [
                    Icon(Icons.info, color: Colors.blue),
                    SizedBox(height: 10),
                    Text(
                      "Location will be updated automatically every 2 minutes, even when the app is closed.",
                      style: TextStyle(
                        color: Colors.blue[800],
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
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