import 'package:flutter/foundation.dart';

import 'speech_engine.dart';

/// The natural voice needs native code, so the web app has only the
/// browser's voices.
const naturalVoiceSupported = false;
const naturalVoiceSize = 0;
const naturalVoices = <SpeechVoice>[];

enum VoiceStatus { missing, downloading, installing, ready, failed }

class NaturalVoiceStore extends ChangeNotifier {
  // Same parameters as the native version, which tests use.
  NaturalVoiceStore({Object? client, Object? root});
  static final instance = NaturalVoiceStore();
  VoiceStatus status = VoiceStatus.missing;
  double progress = 0;
  String? error;
  Future<String?> get modelDir async => null;
  Future<void> check() async {}
  Future<void> download() async {}
  void cancel() {}
  Future<void> remove() async {}
}

class NaturalSpeech extends SpeechEngine {
  NaturalSpeech({required this.modelDir});
  final String modelDir;
  int speaker = 1;
  double rate = 1;
  static Future<void> release() async {}
  @override
  Future<bool> speak(String text) =>
      throw UnsupportedError('The natural voice is not available here.');
  @override
  Future<void> stop() async {}
}
