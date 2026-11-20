import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../speech/natural_voice.dart';
import '../speech/speech.dart';
import '../speech/speech_engine.dart';
import '../ui/components.dart';
import '../ui/tokens.dart';
import 'read_aloud.dart';

/// Controls shown at the bottom of the page while a book is read aloud.
class ReadAloudBar extends StatelessWidget {
  const ReadAloudBar({
    super.key,
    required this.aloud,
    required this.onVoice,
    required this.onClose,
  });
  final ReadAloud aloud;
  final VoidCallback onVoice, onClose;

  static const _speeds = [.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context) {
    final speech = Speech.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([aloud, speech]),
      builder: (context, _) {
        final rate = speech.rate;
        return GlassBar(
          radius: 22,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Previous sentence',
                  icon: const Icon(CupertinoIcons.backward_fill),
                  onPressed: () => aloud.skip(-1),
                ),
                IconButton(
                  key: const Key('read-aloud-play'),
                  tooltip: aloud.playing ? 'Pause' : 'Play',
                  iconSize: 30,
                  icon: Icon(
                    aloud.playing
                        ? CupertinoIcons.pause_fill
                        : CupertinoIcons.play_fill,
                  ),
                  onPressed: aloud.playing ? aloud.pause : aloud.play,
                ),
                IconButton(
                  tooltip: 'Next sentence',
                  icon: const Icon(CupertinoIcons.forward_fill),
                  onPressed: () => aloud.skip(1),
                ),
                TextButton(
                  key: const Key('read-aloud-speed'),
                  onPressed: () {
                    // Cycle through the usual speeds.
                    final i = _speeds.indexWhere((s) => s > rate + .01);
                    final next = i < 0 ? _speeds.first : _speeds[i];
                    speech.update((s) => s.rate = next);
                  },
                  child: Text(
                    '${_format(rate)}×',
                    semanticsLabel: 'Speed ${_format(rate)} times',
                  ),
                ),
                IconButton(
                  tooltip: 'Voice',
                  icon: const Icon(CupertinoIcons.person_crop_circle),
                  onPressed: onVoice,
                ),
                IconButton(
                  tooltip: 'Stop reading aloud',
                  icon: const Icon(CupertinoIcons.xmark),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _format(double rate) =>
    rate == rate.roundToDouble() ? rate.toStringAsFixed(1) : '$rate';

/// Picks the voice: the phone's own, or the natural voice (downloaded on
/// request), its speaker, and the speed.
Future<void> showVoiceSheet(BuildContext context, {String language = 'en'}) =>
    showAppleSheet<void>(
      context: context,
      medium: true,
      initial: .7,
      builder: (context, scroll) =>
          VoiceSheet(language: language, scroll: scroll),
    );

class VoiceSheet extends StatefulWidget {
  const VoiceSheet({super.key, this.language = 'en', this.scroll});
  final String language;
  final ScrollController? scroll;

  @override
  State<VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<VoiceSheet> {
  final speech = Speech.instance;
  final store = NaturalVoiceStore.instance;
  late Future<List<SpeechVoice>> _phoneVoices;

  @override
  void initState() {
    super.initState();
    store.check();
    _phoneVoices = speech.phoneVoices(widget.language);
  }

  Future<void> _preview() async {
    try {
      await speech.say('This is how I sound reading your book.');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('This voice isn’t available.')),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final side = Space.margin(MediaQuery.sizeOf(context).width);
    return ListenableBuilder(
      listenable: Listenable.merge([speech, store]),
      builder: (context, _) {
        final natural = speech.kind == VoiceKind.natural;
        final ready = store.status == VoiceStatus.ready;
        return ListView(
          controller: widget.scroll,
          padding: EdgeInsets.fromLTRB(side, 0, side, Space.xxl),
          children: [
            Text('Read Aloud', style: TextStyles.title2),
            const SizedBox(height: Space.m),
            RadioGroup<VoiceKind>(
              groupValue: natural && ready
                  ? VoiceKind.natural
                  : VoiceKind.phone,
              onChanged: (k) => speech.update((s) => s.kind = k!),
              child: Column(
                children: [
                  const RadioListTile(
                    key: Key('voice-phone'),
                    contentPadding: EdgeInsets.zero,
                    value: VoiceKind.phone,
                    title: Text('Phone voice'),
                    subtitle: Text('Your phone’s text-to-speech'),
                  ),
                  if (naturalVoiceSupported)
                    RadioListTile(
                      key: const Key('voice-natural'),
                      contentPadding: EdgeInsets.zero,
                      value: VoiceKind.natural,
                      enabled: ready,
                      title: const Text('Natural voice'),
                      subtitle: Text(
                        ready
                            ? 'Built-in AI voice · works offline'
                            : 'A more natural AI voice that works offline. '
                                  'Download it once ($naturalVoiceSize MB).',
                      ),
                    ),
                ],
              ),
            ),
            if (naturalVoiceSupported) _download(muted),
            const SizedBox(height: Space.l),
            Row(
              children: [
                Expanded(child: Text('Speaker', style: TextStyles.headline)),
                TextButton.icon(
                  key: const Key('voice-preview'),
                  onPressed: _preview,
                  icon: const Icon(CupertinoIcons.play_circle),
                  label: const Text('Preview'),
                ),
              ],
            ),
            if (natural && ready)
              _speakers(naturalVoices, speech.naturalVoice, (id) {
                speech.update((s) => s.naturalVoice = id);
              })
            else
              FutureBuilder<List<SpeechVoice>>(
                future: _phoneVoices,
                builder: (context, snap) {
                  final voices = snap.data ?? const <SpeechVoice>[];
                  return _speakers(
                    [const SpeechVoice('', 'Phone default'), ...voices],
                    speech.phoneVoice ?? '',
                    (id) => speech.update(
                      (s) => s.phoneVoice = id.isEmpty ? null : id,
                    ),
                  );
                },
              ),
            const SizedBox(height: Space.l),
            Text(
              'Speed · ${_format(speech.rate)}×',
              style: TextStyles.headline,
            ),
            Slider(
              key: const Key('voice-speed'),
              value: speech.rate,
              min: .5,
              max: 2,
              divisions: 15,
              label: '${_format(speech.rate)}×',
              onChanged: (v) =>
                  speech.update((s) => s.rate = (v * 10).round() / 10),
            ),
          ],
        );
      },
    );
  }

  Widget _download(Color muted) {
    switch (store.status) {
      case VoiceStatus.ready:
        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () async {
              await store.remove();
              await speech.update((s) => s.kind = VoiceKind.phone);
            },
            child: const Text('Remove natural voice'),
          ),
        );
      case VoiceStatus.downloading:
      case VoiceStatus.installing:
        final installing = store.status == VoiceStatus.installing;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: installing ? null : store.progress,
              ),
              const SizedBox(height: Space.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      installing
                          ? 'Installing… this can take a minute.'
                          : 'Downloading ${(store.progress * 100).round()}%',
                      style: TextStyles.footnote.copyWith(color: muted),
                    ),
                  ),
                  if (!installing)
                    TextButton(
                      onPressed: store.cancel,
                      child: const Text('Cancel'),
                    ),
                ],
              ),
            ],
          ),
        );
      case VoiceStatus.missing:
      case VoiceStatus.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (store.error case final e?)
              Text(
                e,
                style: TextStyles.footnote.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            FilledButton.tonalIcon(
              key: const Key('voice-download'),
              onPressed: () async {
                await store.download();
                if (store.status == VoiceStatus.ready) {
                  await speech.update((s) => s.kind = VoiceKind.natural);
                }
              },
              icon: const Icon(CupertinoIcons.cloud_download),
              label: Text('Download natural voice ($naturalVoiceSize MB)'),
            ),
          ],
        );
    }
  }

  Widget _speakers(
    List<SpeechVoice> voices,
    String selected,
    ValueChanged<String> onSelect,
  ) => RadioGroup<String>(
    groupValue: selected,
    onChanged: (id) => onSelect(id!),
    child: Column(
      children: [
        for (final v in voices)
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: v.id,
            title: Text(v.name),
            subtitle: v.detail.isEmpty ? null : Text(v.detail),
          ),
      ],
    ),
  );
}
