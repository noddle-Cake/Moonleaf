import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/components.dart';
import '../ui/tokens.dart';
import 'dictionary.dart';

/// A short definition shown above the edit menu when a word is held, like
/// the dictionary card on a Kindle. Tapping it opens the full definition.
class DefinitionPreview extends StatelessWidget {
  const DefinitionPreview({
    super.key,
    required this.word,
    required this.language,
    required this.color,
    required this.onOpen,
    this.dictionary,
  });
  final String word, language;
  final Color color;
  final VoidCallback onOpen;
  final Dictionary? dictionary;

  @override
  Widget build(BuildContext context) {
    final muted = color.withValues(alpha: .65);
    return FutureBuilder<Definition?>(
      // Keyed by word so a new selection looks up again.
      key: ValueKey('$language:$word'),
      future: (dictionary ?? Dictionary.instance).define(
        word,
        language: language,
      ),
      builder: (context, snap) {
        final definition = snap.data;
        final meaning = definition?.meanings.first;
        final String body;
        if (snap.connectionState != ConnectionState.done) {
          body = 'Looking up…';
        } else if (meaning == null) {
          body = 'No definition found. Tap to search Wiktionary.';
        } else {
          body = meaning.senses.first.definition;
        }
        return Semantics(
          button: true,
          label: 'Definition of $word',
          child: InkWell(
            key: const Key('definition-preview'),
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: meaning?.lemma ?? word,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (meaning != null)
                          TextSpan(
                            text: '  ${meaning.partOfSpeech}',
                            style: TextStyle(
                              color: muted,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                    style: TextStyles.subheadline.copyWith(color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: TextStyles.footnote.copyWith(color: color),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Shows everything the dictionary has for [text] in a sheet.
Future<void> showDefinition(
  BuildContext context,
  String text, {
  String language = 'en',
  Dictionary? dictionary,
}) => showAppleSheet<void>(
  context: context,
  medium: true,
  builder: (context, scroll) => DefinitionSheet(
    text: text,
    language: language,
    scroll: scroll,
    dictionary: dictionary,
  ),
);

class DefinitionSheet extends StatelessWidget {
  const DefinitionSheet({
    super.key,
    required this.text,
    required this.language,
    this.scroll,
    this.dictionary,
  });
  final String text, language;
  final ScrollController? scroll;
  final Dictionary? dictionary;

  /// Senses shown per part of speech; WordNet has dozens for common verbs.
  static const _senses = 8;

  Uri get _wiktionary => Uri.https(
    'en.wiktionary.org',
    '/wiki/Special:Search',
    {'search': text.contains(' ') ? text : text.toLowerCase(), 'go': 'Go'},
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final side = Space.margin(MediaQuery.sizeOf(context).width);
    return FutureBuilder<Definition?>(
      future: (dictionary ?? Dictionary.instance).define(
        text,
        language: language,
      ),
      builder: (context, snap) {
        final definition = snap.data;
        final done = snap.connectionState == ConnectionState.done;
        return ListView(
          controller: scroll,
          padding: EdgeInsets.fromLTRB(side, 0, side, Space.xxl),
          children: [
            Text(text, style: TextStyles.title2),
            const SizedBox(height: Space.s),
            if (!done)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Space.xl),
                child: CupertinoActivityIndicator(),
              )
            else if (definition == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.l),
                child: Text(
                  'No definition found.',
                  style: TextStyles.body.copyWith(color: muted),
                ),
              )
            else
              for (final m in definition.meanings) ...[
                const SizedBox(height: Space.m),
                Text(
                  m.lemma == null
                      ? m.partOfSpeech
                      : '${m.partOfSpeech} · ${m.lemma}',
                  style: TextStyles.subheadline.copyWith(
                    color: muted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                for (var i = 0; i < m.senses.length && i < _senses; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.s),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text('${i + 1}.', style: TextStyles.body),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.senses[i].definition,
                                style: TextStyles.body,
                              ),
                              if (m.senses[i].example case final e?)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    e,
                                    style: TextStyles.callout.copyWith(
                                      color: muted,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            if (done) ...[
              const SizedBox(height: Space.xl),
              if (definition?.offline ?? false)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s),
                  child: Text(
                    'From the built-in dictionary (WordNet), used while '
                    'Wiktionary can’t be reached.',
                    style: TextStyles.footnote.copyWith(color: muted),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => launchUrl(
                    _wiktionary,
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(CupertinoIcons.arrow_up_right_square),
                  label: const Text('Open in Wiktionary'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
