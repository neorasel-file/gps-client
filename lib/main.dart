import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyBrGg9b0imBQeMwWRY7mzlA1NRvEPYf9cs",
      appId: "1:949505133415:web:9b473ab7d49ac874d43dc2",
      messagingSenderId: "949505133415",
      projectId: "pa-thef",
      databaseURL: "https://pa-thef-default-rtdb.firebaseio.com",
    ),
  );

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ClientTrackerApp(),
  ));
}

class ClientTrackerApp extends StatefulWidget {
  const ClientTrackerApp({super.key});

  @override
  State<ClientTrackerApp> createState() => _ClientTrackerAppState();
}

class _ClientTrackerAppState extends State<ClientTrackerApp> {
  final TextEditingController _nameController = TextEditingController(text: "dev_1");
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final Battery _battery = Battery();

  String currentDeviceId = "dev_1";
  StreamSubscription<Position>? _positionSub;
  bool isTracking = false;
  String currentStatus = "Idle";
  String coordsDisplay = "Lat: --, Lng: --";
  String batteryDisplay = "--%";

  @override
  void initState() {
    super.initState();
    _loadSavedDeviceId();
  }

  Future<void> _loadSavedDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      currentDeviceId = prefs.getString('saved_device_id') ?? "dev_1";
      _nameController.text = currentDeviceId;
    });
  }

  Future<void> _saveDeviceId() async {
    final newId = _nameController.text.trim();
    if (newId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_device_id', newId);

    if (isTracking) {
      _stopTracking();
      setState(() => currentDeviceId = newId);
      _startTracking();
    } else {
      setState(() => currentDeviceId = newId);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Device ID saved: $newId')),
      );
    }
  }

  Future<void> _startTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => currentStatus = "Turn on GPS");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => currentStatus = "Permission denied");
        return;
      }
    }

    setState(() {
      isTracking = true;
      currentStatus = "Broadcasting Coordinates";
    });

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position pos) async {
      int batLevel = await _battery.batteryLevel;
      
      _dbRef.child("tracking/$currentDeviceId").set({
        "latitude": pos.latitude,
        "longitude": pos.longitude,
        "speed": pos.speed,
        "battery_level": batLevel,
        "updated_at": ServerValue.timestamp,
      });

      setState(() {
        coordsDisplay = "Lat: ${pos.latitude.toStringAsFixed(4)}, Lng: ${pos.longitude.toStringAsFixed(4)}";
        batteryDisplay = "$batLevel%";
      });
    });
  }

  void _stopTracking() {
    _positionSub?.cancel();
    setState(() {
      isTracking = false;
      currentStatus = "Stopped";
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text("Target Tracking Client", style: TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: SingleChildScrollView(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Device ID", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: "Enter ID (e.g. dev_1)",
                            hintStyle: TextStyle(color: Colors.white30),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _saveDeviceId,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        child: const Text("Save", style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Icon(Icons.radar, size: 70, color: isTracking ? Colors.blueAccent : Colors.grey),
            const SizedBox(height: 16),
            Text("Active: $currentDeviceId", style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(currentStatus, style: const TextStyle(color: Colors.blueAccent, fontSize: 13)),
            const SizedBox(height: 24),
            Text(coordsDisplay, style: const TextStyle(color: Colors.white70, fontFamily: 'monospace')),
            const SizedBox(height: 4),
            Text("Battery: $batteryDisplay", style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isTracking ? Colors.redAccent : Colors.blueAccent,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
              onPressed: isTracking ? _stopTracking : _startTracking,
              child: Text(isTracking ? "STOP SERVICE" : "START BROADCAST", style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
