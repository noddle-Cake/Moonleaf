import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/device.dart';
import '../ui/components.dart';
import '../ui/tokens.dart';
import 'library_store.dart';

const _seenKey = 'moonleaf_welcome_seen';

/// Shows the welcome guide once, the first time the app opens.
Future<void> showWelcomeOnce(BuildContext context, LibraryStore store) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_seenKey) ?? false) return;
  if (!context.mounted) return;
  await showWelcome(context, store);
  await prefs.setBool(_seenKey, true);
}

/// How Moonleaf works, in four points, with the e-ink choice.
Future<void> showWelcome(BuildContext context, LibraryStore store) =>
    showAppleSheet<void>(
      context: context,
      builder: (context, _) => _Welcome(store: store),
    );

class _Welcome extends StatefulWidget {
  const _Welcome({required this.store});
  final LibraryStore store;
  @override
  State<_Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<_Welcome> {
  late bool _eink =
      widget.store.appearance == AppAppearance.ereaderLight ||
      widget.store.appearance == AppAppearance.ereaderDark ||
      Device.eink;

  Future<void> _done() async {
    final store = widget.store;
    final ereader =
        store.appearance == AppAppearance.ereaderLight ||
        store.appearance == AppAppearance.ereaderDark;
    try {
      if (_eink && !ereader) {
        await store.setAppearance(theme: AppAppearance.ereaderLight);
      } else if (!_eink && ereader) {
        await store.setAppearance(theme: AppAppearance.system);
      }
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final side = Space.margin(MediaQuery.sizeOf(context).width);
    Widget point(IconData icon, String title, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 44, child: Icon(icon, size: 30, color: p.accent)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyles.headline.copyWith(color: p.label),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: TextStyles.subheadline.copyWith(
                    color: p.secondaryLabel,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(side + 8, 8, side + 8, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Welcome to Moonleaf',
              textAlign: TextAlign.center,
              style: TextStyles.largeTitle.copyWith(
                color: p.label,
                fontFamily: 'Fraunces',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Web novels as books you can read anywhere, even offline.',
              textAlign: TextAlign.center,
              style: TextStyles.body.copyWith(color: p.secondaryLabel),
            ),
            const SizedBox(height: 30),
            point(
              CupertinoIcons.square_arrow_up,
              'Add from your browser',
              'On a story or chapter page, tap Share, then Moonleaf. Or copy '
                  'the link and tap + in Library to paste it.',
            ),
            point(
              CupertinoIcons.bookmark,
              'Start where you are',
              'Share a link to chapter 21 and the book opens there, with '
                  'chapters 1 to 20 marked as read.',
            ),
            point(
              CupertinoIcons.arrow_down_circle,
              'Read while it downloads',
              'The book opens after its first chapter. The rest keep '
                  'downloading, even with the app in the background.',
            ),
            point(
              CupertinoIcons.hand_draw,
              'Turn pages your way',
              'Tap the sides of a page or use the volume buttons. Tap the '
                  'middle for the menu and settings.',
            ),
            GroupedSection(
              margin: EdgeInsets.zero,
              footer: Device.eink
                  ? 'This looks like an e-ink device, so this is on.'
                  : 'For e-paper screens such as Hisense, Boox and Kobo.',
              children: [
                SwitchRow(
                  key: const Key('welcome-eink'),
                  title: 'E-ink Screen',
                  subtitle: 'Black and white, no animation or flashing',
                  value: _eink,
                  onChanged: (v) => setState(() => _eink = v),
                ),
              ],
            ),
            const SizedBox(height: 24),
            CapsuleButton(
              key: const Key('welcome-continue'),
              label: 'Continue',
              onPressed: _done,
            ),
          ],
        ),
      ),
    );
  }
}
