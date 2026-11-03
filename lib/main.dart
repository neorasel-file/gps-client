import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

const firebaseOptions = FirebaseOptions(
  apiKey: "AIzaSyBrGg9b0imBQeMwWRY7mzlA1NRvEPYf9cs",
  appId: "1:949505133415:web:9b473ab7d49ac874d43dc2",
  messagingSenderId: "949505133415",
  projectId: "pa-thef",
  databaseURL: "https://pa-thef-default-rtdb.firebaseio.com",
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: firebaseOptions);
    await initializeService();
  } catch (e) {
    debugPrint("Init error: $e");
  }

  runApp(const MaterialApp(
    title: "NeoFind",
    debugShowCheckedModeBanner: false,
    home: ClientTrackerApp(),
  ));
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'neofind_channel',
      initialNotificationTitle: 'NeoFind Live Tracking',
      initialNotificationContent: 'GPS Service is active',
      foregroundServiceNotificationId: 999,
    ),
    iosConfiguration: IosConfiguration(),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  try {
    await Firebase.initializeApp(options: firebaseOptions);
  } catch (_) {}

  final DatabaseReference dbRef = FirebaseDatabase.instance.ref();
  final Battery battery = Battery();
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  String currentDeviceId = prefs.getString('saved_device_id') ?? "dev_1";

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  service.on('updateDeviceId').listen((event) {
    if (event != null && event['id'] != null) {
      currentDeviceId = event['id'];
    }
  });

  const locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 5,
  );

  Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position pos) async {
    try {
      int batLevel = await battery.batteryLevel;
      dbRef.child("tracking/$currentDeviceId").set({
        "latitude": pos.latitude,
        "longitude": pos.longitude,
        "speed": pos.speed,
        "battery_level": batLevel,
        "updated_at": ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint("DB write error: $e");
    }
  }, onError: (err) {
    debugPrint("Location stream error: $err");
  });
}

class ClientTrackerApp extends StatefulWidget {
  const ClientTrackerApp({super.key});

  @override
  State<ClientTrackerApp> createState() => _ClientTrackerAppState();
}

class _ClientTrackerAppState extends State<ClientTrackerApp> {
  final TextEditingController _nameController = TextEditingController(text: "dev_1");
  final FlutterBackgroundService _service = FlutterBackgroundService();
  bool isRunning = false;
  String currentDeviceId = "dev_1";

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    currentDeviceId = prefs.getString('saved_device_id') ?? "dev_1";
    _nameController.text = currentDeviceId;
    bool running = await _service.isRunning();
    setState(() {
      isRunning = running;
    });
  }

  Future<void> _saveDeviceId() async {
    final newId = _nameController.text.trim();
    if (newId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_device_id', newId);
    _service.invoke('updateDeviceId', {'id': newId});

    setState(() => currentDeviceId = newId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved: $newId')),
      );
    }
  }

  Future<void> _toggleService() async {
    if (isRunning) {
      _service.invoke('stopService');
      setState(() => isRunning = false);
    } else {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable GPS/Location')),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission is required')),
          );
        }
        return;
      }

      await _service.startService();
      setState(() => isRunning = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text("NeoFind Client", style: TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: "Device ID",
                        hintStyle: TextStyle(color: Colors.white30),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saveDeviceId,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                    child: const Text("Save", style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
            Icon(Icons.radar, size: 70, color: isRunning ? Colors.blueAccent : Colors.grey),
            const SizedBox(height: 16),
            Text(
              isRunning ? "NeoFind Active in Background" : "NeoFind Idle",
              style: TextStyle(color: isRunning ? Colors.greenAccent : Colors.redAccent, fontSize: 14),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isRunning ? Colors.redAccent : Colors.blueAccent,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
              onPressed: _toggleService,
              child: Text(isRunning ? "STOP SERVICE" : "START BACKGROUND TRACKING", style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
