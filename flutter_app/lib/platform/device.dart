import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Facts about the device that the app can't read from Flutter alone.
class Device {
  Device._();

  static const _channel = MethodChannel('moonleaf/device');

  /// Brands whose Android devices use e-paper screens.
  static const einkBrands = [
    'hisense',
    'onyx',
    'boox',
    'kobo',
    'pocketbook',
    'bigme',
    'meebook',
    'boyue',
    'likebook',
    'dasung',
    'moaan',
    'inkpalm',
    'hyread',
    'tolino',
    'mooink',
    'xteink',
  ];

  /// Whether this looks like an e-ink device. Set by [load].
  static bool eink = false;

  /// Reads the maker and model once at startup. Never throws.
  static Future<void> load() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final info = await _channel.invokeMapMethod<String, String>('info');
      if (info != null) eink = looksLikeEink(info.values.join(' '));
    } catch (_) {}
  }

  @visibleForTesting
  static bool looksLikeEink(String makerAndModel) {
    final text = makerAndModel.toLowerCase();
    return einkBrands.any(text.contains);
  }
}
