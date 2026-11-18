// Live check of the in-app browser against a real site with a human check.
// When the site's check appears in the app window, complete it within three
// minutes. Runs only with an explicit URL, for example:
//   flutter test integration_test/browser_live_test.dart -d macos \
//     --dart-define=LIVE_URL=https://www.scribblehub.com/
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:novel_to_epub/browser/browser_loader.dart';

const liveUrl = String.fromEnvironment('LIVE_URL');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'browser loads a page past the human check',
    (tester) async {
      final loader = BrowserLoader(challengeGrace: const Duration(seconds: 20));
      await tester.pumpWidget(
        MaterialApp(
          home: BrowserHost(
            loader: loader,
            child: const Scaffold(body: Text('host')),
          ),
        ),
      );
      final result = loader.load(Uri.parse(liveUrl));
      String? page;
      Object? error;
      result.then<void>(
        (p) => page = p,
        onError: (Object e) {
          error = e;
        },
      );
      final started = DateTime.now();
      var askedYou = false;
      var ticks = 0;
      while (page == null && error == null) {
        await tester.pump(const Duration(milliseconds: 500));
        askedYou |= loader.needsYou;
        if (++ticks % 10 == 0) {
          final title = await loader.controller
              ?.runJavaScriptReturningResult(
                'document.title + " | " + document.readyState + " | " + location.href',
              )
              .catchError((Object e) => 'js error $e');
          // ignore: avoid_print
          print('LIVE TICK ${ticks ~/ 2}s needsYou=${loader.needsYou} $title');
        }
        if (DateTime.now().difference(started) > const Duration(minutes: 3)) {
          loader.giveUp();
        }
      }
      // ignore: avoid_print
      print(
        'LIVE RESULT: error=$error askedYou=$askedYou '
        'length=${page?.length} title=${RegExp(r'<title>([^<]*)').firstMatch(page ?? '')?[1]}',
      );
      expect(error, isNull);
      expect(page, isNot(contains('challenge-platform')));
    },
    skip: liveUrl.isEmpty,
  );
}
