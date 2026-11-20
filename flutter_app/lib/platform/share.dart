import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Links shared to Moonleaf from other apps ("Share → Moonleaf").
class SharedLinks {
  SharedLinks._();

  static const _channel = MethodChannel('moonleaf/share');

  /// The newest shared link the app hasn't handled yet.
  static final link = ValueNotifier<String?>(null);

  static Future<void> start() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared') _receive(call.arguments as String?);
    });
    try {
      _receive(await _channel.invokeMethod<String>('take'));
    } catch (_) {}
  }

  static void _receive(String? text) {
    final url = text == null ? null : firstLink(text);
    if (url != null) link.value = url;
  }

  /// The first web link in shared text. Browsers share the link alone, but
  /// some apps add the page title around it.
  static String? firstLink(String text) {
    final match = RegExp(r'''https?://[^\s<>"']+''').firstMatch(text);
    return match?.group(0)?.replaceFirst(RegExp(r'[).,;:!?]+$'), '');
  }
}
