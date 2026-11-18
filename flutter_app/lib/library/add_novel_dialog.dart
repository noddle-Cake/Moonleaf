import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../data/novel_service.dart';
import '../data/site_extractors.dart';
import '../ui/tokens.dart';
import 'library_store.dart';

/// The Add a Novel sheet: Cancel and Add at the top, a link field below.
/// Pops with the novel's library address once it's saved.
class AddNovelDialog extends StatefulWidget {
  const AddNovelDialog({
    super.key,
    required this.store,
    required this.service,
    this.initialUrl,
  });
  final LibraryStore store;
  final NovelService service;
  final String? initialUrl;
  @override
  State<AddNovelDialog> createState() => _AddNovelDialogState();
}

class _AddNovelDialogState extends State<AddNovelDialog> {
  late final _url = TextEditingController(text: widget.initialUrl ?? '');
  bool _busy = false;
  String? _error;
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
      extractorFor(Uri.parse(url));
      final metadata = await widget.service.detect(url);
      if (!mounted) return;
      // A chapter link is saved under its novel's main page.
      final saved = metadata.url.isEmpty ? url : metadata.url;
      await widget.store.add(saved, metadata);
      // Return the library key so the caller can open and download it.
      if (mounted) {
        Navigator.pop(context, widget.store.find(saved)?.url ?? saved);
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
                  autofocus: true,
                  enabled: !_busy,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) {
                    if (!_busy) _add();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Novel or chapter URL',
                    hintText: 'https://www.royalroad.com/fiction/…',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _error ??
                      'Paste a story page, or a link to any of its chapters, '
                          'from Royal Road, Scribble Hub, FanFiction.net, AO3, '
                          'Standard Ebooks or RoliaScan. Moonleaf adds it to '
                          'your library and downloads the chapters.',
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
