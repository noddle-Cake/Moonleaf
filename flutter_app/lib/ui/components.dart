import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

/// An inset, rounded group of rows, like Settings on iPhone. Rows are
/// separated by hairlines inset from the leading edge.
class GroupedSection extends StatelessWidget {
  const GroupedSection({
    super.key,
    this.header,
    this.footer,
    required this.children,
    this.margin,
  });
  final String? header, footer;
  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final side = Space.margin(MediaQuery.sizeOf(context).width);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 16),
            child: Divider(height: .5, thickness: .5, color: p.separator),
          ),
        );
      }
      rows.add(children[i]);
    }
    return Padding(
      padding: margin ?? EdgeInsets.fromLTRB(side, 0, side, Space.xxl - 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
              child: Text(
                header!,
                style: TextStyles.headline.copyWith(color: p.label),
              ),
            ),
          Material(
            color: p.cell,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.section),
              side: p.eink ? BorderSide(color: p.separator) : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(mainAxisSize: MainAxisSize.min, children: rows),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
              child: Text(
                footer!,
                style: TextStyles.footnote.copyWith(color: p.secondaryLabel),
              ),
            ),
        ],
      ),
    );
  }
}

/// A row for [GroupedSection]: at least 44 pt tall, with an optional
/// leading icon, value text and trailing chevron.
class GroupedRow extends StatelessWidget {
  const GroupedRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.value,
    this.trailing,
    this.onTap,
    this.chevron = false,
    this.destructive = false,
  });
  final String title;
  final String? subtitle, value;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron, destructive;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = destructive ? p.destructive : p.label;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minTarget + 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 22,
                  color: destructive ? p.destructive : p.accent,
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: TextStyles.body.copyWith(color: color)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: TextStyles.subheadline.copyWith(
                            color: p.secondaryLabel,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (value != null)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      value!,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyles.body.copyWith(color: p.secondaryLabel),
                    ),
                  ),
                ),
              ?trailing,
              if (chevron)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    CupertinoIcons.chevron_forward,
                    size: 17,
                    color: p.tertiaryLabel,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row with an iOS-style switch.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return MergeSemantics(
      child: GroupedRow(
        title: title,
        subtitle: subtitle,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: CupertinoSwitch(
          value: value,
          activeTrackColor: p.accent,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// A translucent, blurred bar (Liquid Glass–style), used sparingly for the
/// tab bar and reader menus. Opaque on e-ink and with high contrast.
class GlassBar extends StatelessWidget {
  const GlassBar({super.key, required this.child, this.radius = 0});
  final Widget child;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final solid = p.eink || MediaQuery.highContrastOf(context);
    final shape = BorderRadius.circular(radius);
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: solid ? p.elevated : p.bar,
        borderRadius: shape,
        border: p.eink
            ? Border.all(color: p.separator)
            : Border.all(color: p.separator.withValues(alpha: .25), width: .5),
      ),
      child: child,
    );
    if (solid) return content;
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: content,
      ),
    );
  }
}

/// Shows a sheet with a grabber. With [medium], it rests at half height
/// and can be dragged to full height.
Future<T?> showAppleSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, ScrollController? scroll)
  builder,
  bool medium = false,
  double initial = .55,
  Color? barrierColor,
}) {
  final p = Palette.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    barrierColor: barrierColor,
    backgroundColor: p.elevated,
    constraints: const BoxConstraints(maxWidth: 700),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
    ),
    builder: (context) => medium
        ? DraggableScrollableSheet(
            expand: false,
            initialChildSize: initial,
            minChildSize: .3,
            maxChildSize: 1,
            snap: true,
            snapSizes: [initial, 1],
            builder: (context, scroll) => builder(context, scroll),
          )
        : builder(context, null),
  );
}

class AlertAction<T> {
  const AlertAction(
    this.label,
    this.value, {
    this.destructive = false,
    this.preferred = false,
  });
  final String label;
  final T value;
  final bool destructive, preferred;
}

/// An Apple-style alert. Returns the chosen action's value, or null.
Future<T?> showAppleAlert<T>({
  required BuildContext context,
  required String title,
  String? message,
  required List<AlertAction<T>> actions,
}) => showCupertinoDialog<T>(
  context: context,
  barrierDismissible: true,
  builder: (context) => CupertinoAlertDialog(
    title: Text(title),
    content: message == null ? null : Text(message),
    actions: [
      for (final a in actions)
        CupertinoDialogAction(
          isDestructiveAction: a.destructive,
          isDefaultAction: a.preferred,
          onPressed: () => Navigator.pop(context, a.value),
          child: Text(a.label),
        ),
    ],
  ),
);

/// A large, prominent capsule button for a screen's main action.
class CapsuleButton extends StatelessWidget {
  const CapsuleButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.prominent = true,
  });
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool prominent;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final style = FilledButton.styleFrom(
      backgroundColor: prominent ? p.accent : p.fill,
      foregroundColor: prominent ? p.onAccent : p.accent,
      minimumSize: const Size(minTarget * 2, 50),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      shape: const StadiumBorder(),
      textStyle: TextStyles.headline,
    );
    return icon == null
        ? FilledButton(onPressed: onPressed, style: style, child: Text(label))
        : FilledButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 20),
            label: Text(label),
          );
  }
}
