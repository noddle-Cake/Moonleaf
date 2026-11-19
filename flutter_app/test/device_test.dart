import 'package:flutter_test/flutter_test.dart';
import 'package:novel_to_epub/platform/device.dart';
import 'package:novel_to_epub/reader/reader_settings.dart';

void main() {
  test('recognizes e-ink makers, including Hisense', () {
    expect(Device.looksLikeEink('Hisense Hisense HLTE556N'), isTrue);
    expect(Device.looksLikeEink('ONYX ONYX NoteAir3'), isTrue);
    expect(Device.looksLikeEink('Kobo Rakuten Kobo'), isTrue);
    expect(Device.looksLikeEink('Google google Pixel 8'), isFalse);
    expect(Device.looksLikeEink('samsung samsung SM-S918B'), isFalse);
  });

  test('e-ink screen setting is automatic by default and saved', () {
    final s = ReaderSettings();
    expect(s.eink, isNull);
    s.eink = true;
    final on = ReaderSettings(s.toJson());
    expect(on.eink, isTrue);
    s.eink = false;
    final off = ReaderSettings(s.toJson());
    expect(off.eink, isFalse);
    for (final x in [s, on, off]) {
      x.dispose();
    }
  });
}
