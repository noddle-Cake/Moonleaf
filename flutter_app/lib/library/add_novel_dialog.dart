import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/novel_service.dart';
import '../data/site_extractors.dart';
import '../platform/share.dart';
import '../ui/tokens.dart';
import 'library_store.dart';

/// A novel added from the Add sheet.
typedef AddedNovel = ({String url, String? from});

/// The Add a Novel sheet: Cancel and Add at the top, a link field below.
/// Pops with an [AddedNovel] once it's saved: the novel's library address,
/// and the pasted chapter link when one was pasted.
class AddNovelDialog extends StatefulWidget {
  const AddNovelDialog({
    super.key,
    required this.store,
    required this.service,
    this.initialUrl,
    this.submit = false,
  });
  final LibraryStore store;
  final NovelService service;
  final String? initialUrl;

  /// Add [initialUrl] right away, as for a link shared from a browser.
  final bool submit;
  @override
  State<AddNovelDialog> createState() => _AddNovelDialogState();
}

class _AddNovelDialogState extends State<AddNovelDialog> {
  late final _url = TextEditingController(text: widget.initialUrl ?? '');
  bool _busy = false;
  String? _error;

  /// Whether the clipboard has text to paste.
  bool _canPaste = false;

  @override
  void initState() {
    super.initState();
    if (widget.submit && (widget.initialUrl ?? '').isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _add();
      });
    }
    // Checking doesn't read the clipboard, so Android shows no notice.
    Clipboard.hasStrings()
        .then((has) {
          if (mounted && has) setState(() => _canPaste = true);
        })
        .catchError((Object _) {});
  }

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    final link = text == null ? null : SharedLinks.firstLink(text);
    if (!mounted) return;
    if (link == null) {
      setState(() => _error = 'The clipboard doesn’t have a link.');
      return;
    }
    _url.text = link;
    setState(() => _error = null);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = _url.text.trim();
      final link = Uri.parse(url);
      final chapter = extractorFor(link).isChapter(link);
      final metadata = await widget.service.detect(url);
      if (!mounted) return;
      // A chapter link is saved under its novel's main page.
      final saved = metadata.url.isEmpty ? url : metadata.url;
      await widget.store.add(saved, metadata);
      // Return the library key so the caller can open and download it.
      if (mounted) {
        Navigator.pop<AddedNovel>(context, (
          url: widget.store.find(saved)?.url ?? saved,
          from: chapter ? url : null,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiException
              ? e.message
              : 'Could not add this novel. Check the link and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final side = Space.margin(MediaQuery.sizeOf(context).width);
    return PopScope(
      canPop: !_busy,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(side, 0, side, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cancel on the leading edge, the main action trailing.
                Row(
                  children: [
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    Expanded(
                      child: Text(
                        'Add a Novel',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyles.headline.copyWith(color: p.label),
                      ),
                    ),
                    _busy
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 18),
                            child: CupertinoActivityIndicator(),
                          )
                        : TextButton(
                            onPressed: _add,
                            child: Text(
                              'Add',
                              style: TextStyles.headline.copyWith(
                                color: p.accent,
                              ),
                            ),
                          ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('add-novel-url'),
                  controller: _url,
                  autofocus: !widget.submit,
                  enabled: !_busy,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) {
                    if (!_busy) _add();
                  },
                  decoration: InputDecoration(
                    labelText: 'Novel or chapter URL',
                    hintText: 'https://www.royalroad.com/fiction/…',
                    suffixIcon: _canPaste && !_busy
                        ? TextButton(
                            key: const Key('paste-link'),
                            onPressed: _paste,
                            child: const Text('Paste'),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _error ??
                      'Copy a story or chapter link in your browser and '
                          'paste it here, or use Share → Moonleaf in the '
                          'browser. Works with Royal Road, Scribble Hub, '
                          'FanFiction.net, AO3, Standard Ebooks and RoliaScan. '
                          'A chapter link starts the book at that chapter.',
                  style: TextStyles.footnote.copyWith(
                    color: _error == null ? p.secondaryLabel : p.destructive,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
