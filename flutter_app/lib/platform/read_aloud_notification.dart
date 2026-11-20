import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Android notification shown while a book is read aloud. Its service
/// keeps the app running with the screen off, and its Pause/Play, Next and
/// Stop buttons come back through [onButton].
class ReadAloudNotification {
  ReadAloudNotification({required void Function(String button) onButton}) {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async => onButton(call.method));
  }

  static const _channel = MethodChannel('moonleaf/readaloud');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  String _last = '';

  void show({
    required String title,
    required String text,
    required bool playing,
  }) {
    if (!supported) return;
    final key = '$title|$text|$playing';
    if (key == _last) return;
    _last = key;
    _channel
        .invokeMethod<bool>('update', {
          'title': title,
          'text': text,
          'playing': playing,
        })
        .catchError((Object _) => false);
  }

  void hide() {
    if (!supported || _last.isEmpty) return;
    _last = '';
    _channel.invokeMethod<void>('stop').catchError((Object _) {});
  }

  void dispose() {
    hide();
    if (supported) _channel.setMethodCallHandler(null);
  }
}
