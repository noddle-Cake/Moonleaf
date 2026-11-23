import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/components.dart';
import '../ui/tokens.dart';
import 'app_updates.dart';

class AppUpdatesScreen extends StatefulWidget {
  const AppUpdatesScreen({super.key, this.controller});
  final AppUpdateController? controller;
  @override
  State<AppUpdatesScreen> createState() => _AppUpdatesScreenState();
}

class _AppUpdatesScreenState extends State<AppUpdatesScreen>
    with WidgetsBindingObserver {
  late final updates = widget.controller ?? AppUpdateController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (updates.phase == UpdatePhase.idle) unawaited(updates.check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(updates.resumed());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) updates.dispose();
    super.dispose();
  }

  Future<void> _open(Uri url) async {
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('Unavailable');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open your browser. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(title: const Text('App Updates')),
      body: ListenableBuilder(
        listenable: updates,
        builder: (context, _) {
          final phase = updates.phase;
          final release = updates.release;
          final title = switch (phase) {
            UpdatePhase.idle || UpdatePhase.checking => 'Checking for updates…',
            UpdatePhase.current => 'You’re up to date',
            UpdatePhase.available => 'Update available',
            UpdatePhase.downloading => 'Downloading update…',
            UpdatePhase.ready => 'Ready to install',
            UpdatePhase.installing => 'Continue in Android',
            UpdatePhase.incompatible => 'This installation needs attention',
            UpdatePhase.unsupported => 'Android app updates',
            UpdatePhase.error => 'Could not check for updates',
          };
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 20),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  children: [
                    Icon(
                      CupertinoIcons.arrow_down_circle,
                      size: 48,
                      color: p.accent,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: TextStyles.title2.copyWith(color: p.label),
                      textAlign: TextAlign.center,
                    ),
                    if (updates.message != null) ...[
                      const SizedBox(height: 12),
                      Text(updates.message!, textAlign: TextAlign.center),
                    ],
                    if (phase == UpdatePhase.checking) ...[
                      const SizedBox(height: 16),
                      const CupertinoActivityIndicator(),
                    ],
                  ],
                ),
              ),
              GroupedSection(
                header: 'Versions',
                children: [
                  GroupedRow(
                    title: 'Installed',
                    subtitle: updates.installed?.label ?? 'Not available',
                  ),
                  if (release != null)
                    GroupedRow(
                      title: 'Latest release',
                      subtitle: release.label,
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (phase == UpdatePhase.incompatible) ...[
                      const Text(
                        'This copy uses a different signing key. Older debug builds need a one-time reinstall. Save your EPUBs before removing the app; uninstalling removes local progress, highlights and settings.',
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => _open(
                          Uri.parse(
                            'https://moonleaf.cjservin.com/download/#old-debug-builds',
                          ),
                        ),
                        child: const Text('Read Migration Instructions'),
                      ),
                    ],
                    if (phase == UpdatePhase.unsupported) ...[
                      const Text(
                        'In-app APK updates are available on Android. You can find the Android download and source code on the website.',
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => _open(
                          Uri.parse('https://moonleaf.cjservin.com/download/'),
                        ),
                        child: const Text('Open Download Page'),
                      ),
                    ],
                    if (phase == UpdatePhase.available)
                      FilledButton(
                        onPressed: updates.download,
                        child: Text('Download Update (${release!.sizeLabel})'),
                      ),
                    if (phase == UpdatePhase.downloading) ...[
                      LinearProgressIndicator(
                        value: updates.received / release!.size,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(updates.received / release.size * 100).floor()}% of ${release.sizeLabel}',
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: updates.cancel,
                        child: const Text('Cancel Download'),
                      ),
                    ],
                    if (phase == UpdatePhase.ready) ...[
                      const Text(
                        'Android will ask you to confirm the update. Your library, progress, highlights and settings stay in place.',
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: updates.install,
                        child: const Text('Install Update'),
                      ),
                    ],
                    if (phase == UpdatePhase.installing)
                      const Text(
                        'Follow Android’s installation prompt. If you cancel, return here to try again.',
                      ),
                    if (!updates.busy && phase != UpdatePhase.unsupported) ...[
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: updates.check,
                        child: Text(
                          phase == UpdatePhase.error
                              ? 'Try Again'
                              : 'Check Again',
                        ),
                      ),
                    ],
                    if (release != null) ...[
                      const SizedBox(height: 24),
                      Text('Release notes', style: TextStyles.headline),
                      const SizedBox(height: 12),
                      SelectableText(
                        release.notes.isEmpty
                            ? 'See the release page for details.'
                            : release.notes,
                      ),
                      TextButton(
                        onPressed: () => _open(release.page),
                        child: const Text('View Release Page'),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Text(
                      'Checks run when you open this screen or tap Check Again. Updates are never installed automatically.',
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
