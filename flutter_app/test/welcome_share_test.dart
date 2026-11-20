// First launch, links shared from a browser, and pasting a link.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novel_to_epub/data/local_novel_service.dart';
import 'package:novel_to_epub/library/add_novel_dialog.dart';
import 'package:novel_to_epub/library/library_screen.dart';
import 'package:novel_to_epub/library/library_store.dart';
import 'package:novel_to_epub/library/welcome_sheet.dart';
import 'package:novel_to_epub/platform/share.dart';
import 'package:novel_to_epub/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const novel = 'https://roliascan.com/manga/sample-novel/';
const chapter = 'https://roliascan.com/read/sample-novel/ch7-130/';
const book =
    '<h1>Sample Novel</h1><a id="start-reading-btn" href="/read/sample-novel/ch1-123/">Read</a>';
const chapterPage =
    '''
<script type="application/ld+json">{"@type":"BreadcrumbList","itemListElement":[
{"@type":"ListItem","position":2,"name":"Sample Novel","item":"$novel"}]}</script>
<div class="reader-text"><p>Chapter text.</p></div>''';

LocalNovelService service() => LocalNovelService(
  client: MockClient((r) async {
    final body = {chapter: chapterPage, novel: book}[r.url.toString()];
    return http.Response(body ?? 'missing', body == null ? 404 : 200);
  }),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('finds the link in shared text', () {
    expect(
      SharedLinks.firstLink(
        'Chapter 7 | Sample Novel https://roliascan.com/read/sample-novel/ch7-130/.',
      ),
      chapter,
    );
    expect(SharedLinks.firstLink('no link here'), isNull);
  });

  testWidgets('the welcome guide shows once and can turn on e-ink', (
    tester,
  ) async {
    final store = LibraryStore();
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: novelTheme(Brightness.light),
        home: Builder(
          builder: (c) {
            context = c;
            return const Scaffold();
          },
        ),
      ),
    );
    showWelcomeOnce(context, store);
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Moonleaf'), findsOneWidget);
    expect(find.text('Add from your browser'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('welcome-eink')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('welcome-eink')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('welcome-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('welcome-continue')));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Moonleaf'), findsNothing);
    expect(store.appearance, AppAppearance.ereaderLight);
    // Not again.
    showWelcomeOnce(context, store);
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Moonleaf'), findsNothing);
  });

  testWidgets('a link shared from a browser is added right away', (
    tester,
  ) async {
    final store = LibraryStore();
    final s = service();
    addTearDown(s.close);
    SharedLinks.link.value = chapter;
    await tester.pumpWidget(
      MaterialApp(
        theme: novelTheme(Brightness.light),
        home: LibraryScreen(store: store, service: s),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
    }
    expect(SharedLinks.link.value, isNull);
    expect(store.novels.single.url, 'https://roliascan.com/manga/sample-novel');
  });

  testWidgets('Paste fills in a copied link', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.hasStrings' => {'value': true},
        'Clipboard.getData' => {'text': 'See $chapter'},
        _ => null,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final s = service();
    addTearDown(s.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddNovelDialog(store: LibraryStore(), service: s),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('paste-link')));
    await tester.pumpAndSettle();
    expect(find.text(chapter), findsOneWidget);
  });
}
