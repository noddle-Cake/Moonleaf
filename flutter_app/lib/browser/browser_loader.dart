import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../data/novel_service.dart';
import '../data/page_loader.dart';

/// Whether this platform has the in-app browser (Android, iOS and macOS).
bool get browserSupported =>
    !kIsWeb &&
    {
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }.contains(defaultTargetPlatform);

/// Loads pages in a WebView for sites that ask visitors to confirm they're
/// human. Pages load out of sight; when a site shows a check that doesn't
/// pass on its own, [BrowserHost] brings the browser forward so the person
/// can complete it, then downloading continues. Pages load one at a time.
class BrowserLoader extends ChangeNotifier implements PageLoader {
  BrowserLoader({this.challengeGrace = const Duration(seconds: 8)});

  /// How long to let a check pass by itself before asking the person.
  final Duration challengeGrace;

  WebViewController? _controller;
  WebViewController? get controller => _controller;

  /// A page is loading (the WebView must be in the widget tree).
  bool get active => _active;
  bool _active = false;

  /// The site wants the person to complete a check.
  bool get needsYou => _needsYou;
  bool _needsYou = false;
  String get host => _host;
  String _host = '';

  Future<void> _queue = Future.value();
  Completer<void>? _finished;
  Completer<void>? _gaveUp;

  @override
  Future<String> load(Uri url) {
    final result = _queue.then((_) => _load(url));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Called when the person closes the check without finishing it.
  void giveUp() {
    final gaveUp = _gaveUp;
    if (gaveUp != null && !gaveUp.isCompleted) gaveUp.complete();
  }

  WebViewController _create() => WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          final done = _finished;
          if (done != null && !done.isCompleted) done.complete();
        },
      ),
    );

  Future<String> _load(Uri url) async {
    final controller = _controller ??= _create();
    _host = url.host.replaceFirst(RegExp(r'^www\.'), '');
    _active = true;
    _gaveUp = Completer<void>();
    notifyListeners();
    try {
      _finished = Completer<void>();
      await controller.loadRequest(url);
      await _wait(_finished!.future, const Duration(seconds: 45));
      final started = DateTime.now();
      while (true) {
        final page = await _html(controller);
        if (!_isCheck(page)) {
          if (await _ready(controller)) return page;
        } else if (!_needsYou &&
            DateTime.now().difference(started) > challengeGrace) {
          _needsYou = true;
          notifyListeners();
        }
        if (DateTime.now().difference(started) > const Duration(minutes: 5)) {
          throw const ApiException(
            'The site’s check didn’t finish. Try again in a moment.',
          );
        }
        final stop = await Future.any([
          Future<bool>.delayed(const Duration(milliseconds: 700), () => false),
          _gaveUp!.future.then((_) => true),
        ]);
        if (stop) {
          throw const ApiException(
            'The download stopped because the site’s check was closed.',
          );
        }
      }
    } finally {
      _needsYou = false;
      _active = false;
      notifyListeners();
    }
  }

  Future<void> _wait(Future<void> future, Duration limit) async {
    try {
      await future.timeout(limit);
    } on TimeoutException {
      // Slow pages still get checked below.
    }
  }

  Future<bool> _ready(WebViewController controller) async =>
      (await _js(controller, 'document.readyState')) == 'complete';

  Future<String> _html(WebViewController controller) async =>
      await _js(controller, 'document.documentElement.outerHTML') ?? '';

  /// Runs JavaScript and returns a string. Android returns JSON-encoded
  /// strings, while Apple platforms return them as is.
  Future<String?> _js(WebViewController controller, String script) async {
    try {
      final value = await controller.runJavaScriptReturningResult(script);
      if (value is String) {
        if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
          try {
            return jsonDecode(value) as String;
          } catch (_) {}
        }
        return value;
      }
      return value.toString();
    } catch (_) {
      return null;
    }
  }

  /// Cloudflare's human check pages.
  static bool _isCheck(String page) =>
      page.contains('challenge-platform') ||
      page.contains('cf-turnstile') ||
      page.contains('id="challenge-form"') ||
      page.contains('<title>Just a moment');
}

/// Hosts the browser: a hidden WebView while pages load, and a full-screen
/// check when a site asks the person to confirm they're human.
class BrowserHost extends StatelessWidget {
  const BrowserHost({super.key, required this.loader, required this.child});
  final BrowserLoader loader;
  final Widget child;
  static final _view = GlobalKey();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: loader,
    builder: (context, _) {
      final controller = loader.controller;
      final show = loader.needsYou;
      return Stack(
        children: [
          child,
          if (loader.active && controller != null)
            // The page stays laid out while hidden so it loads normally.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !show,
                child: Opacity(
                  opacity: show ? 1 : 0,
                  child: _Check(
                    host: loader.host,
                    onClose: loader.giveUp,
                    child: WebViewWidget(key: _view, controller: controller),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _Check extends StatelessWidget {
  const _Check({
    required this.host,
    required this.onClose,
    required this.child,
  });
  final String host;
  final VoidCallback onClose;
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: Text('Quick check from $host'),
            subtitle: const Text(
              'The site asks visitors to confirm they’re human. Complete the '
              'check below and Moonleaf will continue downloading.',
            ),
            trailing: IconButton(
              tooltip: 'Stop downloading',
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
          ),
          const Divider(height: 1),
          Expanded(child: child),
        ],
      ),
    ),
  );
}
