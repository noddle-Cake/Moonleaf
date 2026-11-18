import 'package:flutter/material.dart';

/// Design tokens following Apple's Human Interface Guidelines: the standard
/// text styles, system-like colors, spacing, corner radii and hit targets.
/// Shared by the app and the reader's menus.

/// Apple's text styles at the default text size (points). Sizes scale with
/// the system text size through [MediaQuery.textScaler].
abstract final class TextStyles {
  static const largeTitle = TextStyle(
    fontSize: 34,
    height: 41 / 34,
    fontWeight: FontWeight.w700,
    letterSpacing: .4,
  );
  static const title1 = TextStyle(
    fontSize: 28,
    height: 34 / 28,
    fontWeight: FontWeight.w700,
    letterSpacing: .38,
  );
  static const title2 = TextStyle(
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -.26,
  );
  static const title3 = TextStyle(
    fontSize: 20,
    height: 25 / 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -.45,
  );
  static const headline = TextStyle(
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -.43,
  );
  static const body = TextStyle(
    fontSize: 17,
    height: 22 / 17,
    letterSpacing: -.43,
  );
  static const callout = TextStyle(
    fontSize: 16,
    height: 21 / 16,
    letterSpacing: -.31,
  );
  static const subheadline = TextStyle(
    fontSize: 15,
    height: 20 / 15,
    letterSpacing: -.23,
  );
  static const footnote = TextStyle(
    fontSize: 13,
    height: 18 / 13,
    letterSpacing: -.08,
  );
  static const caption1 = TextStyle(fontSize: 12, height: 16 / 12);
  static const caption2 = TextStyle(
    fontSize: 11,
    height: 13 / 11,
    letterSpacing: .06,
  );
}

abstract final class Space {
  static const xs = 4.0, s = 8.0, m = 12.0, l = 16.0, xl = 20.0, xxl = 32.0;

  /// Side margin for content: 16 pt on narrow phones, 20 pt otherwise.
  static double margin(double width) => width < 375 ? 16 : 20;
}

abstract final class Radii {
  /// Grouped list sections and cards.
  static const section = 26.0;

  /// Rows, small cards and covers.
  static const small = 10.0;

  /// Sheets.
  static const sheet = 34.0;
}

/// Smallest comfortable hit target (44 × 44 pt).
const minTarget = 44.0;

/// Width below which layouts switch to their compact (slim phone) form.
const compactWidth = 360.0;

/// The app's colors in one mode. Mirrors Apple's semantic system colors with
/// Moonleaf's green as the single accent.
class Palette {
  const Palette({
    required this.dark,
    required this.background,
    required this.cell,
    required this.elevated,
    required this.label,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.separator,
    required this.fill,
    required this.accent,
    required this.onAccent,
    required this.destructive,
    required this.bar,
  });
  final bool dark;

  /// Grouped background, behind sections.
  final Color background;

  /// Rows and cards on the grouped background.
  final Color cell;

  /// Sheets, menus and dialogs.
  final Color elevated;
  final Color label, secondaryLabel, tertiaryLabel, separator, fill;
  final Color accent, onAccent, destructive;

  /// Translucent bar tint (tab bar, reader menus).
  final Color bar;

  static const light = Palette(
    dark: false,
    background: Color(0xFFF2F2F7),
    cell: Color(0xFFFFFFFF),
    elevated: Color(0xFFFFFFFF),
    label: Color(0xFF000000),
    secondaryLabel: Color(0x993C3C43),
    tertiaryLabel: Color(0x4D3C3C43),
    separator: Color(0x4A3C3C43),
    fill: Color(0x1F787880),
    accent: Color(0xFF247A65),
    onAccent: Color(0xFFFFFFFF),
    destructive: Color(0xFFD70015),
    bar: Color(0xD9F9F9F9),
  );

  static const darkMode = Palette(
    dark: true,
    background: Color(0xFF000000),
    cell: Color(0xFF1C1C1E),
    elevated: Color(0xFF2C2C2E),
    label: Color(0xFFFFFFFF),
    secondaryLabel: Color(0x99EBEBF5),
    tertiaryLabel: Color(0x4DEBEBF5),
    separator: Color(0x99545458),
    fill: Color(0x3D767680),
    accent: Color(0xFF6FD3B7),
    onAccent: Color(0xFF00241B),
    destructive: Color(0xFFFF6961),
    bar: Color(0xCC161618),
  );

  /// Pure black and white for e-ink screens: no translucency, no tints.
  static const einkLight = Palette(
    dark: false,
    background: Color(0xFFFFFFFF),
    cell: Color(0xFFFFFFFF),
    elevated: Color(0xFFFFFFFF),
    label: Color(0xFF000000),
    secondaryLabel: Color(0xFF333333),
    tertiaryLabel: Color(0xFF666666),
    separator: Color(0xFF000000),
    fill: Color(0xFFEEEEEE),
    accent: Color(0xFF000000),
    onAccent: Color(0xFFFFFFFF),
    destructive: Color(0xFF000000),
    bar: Color(0xFFFFFFFF),
  );

  static const einkDark = Palette(
    dark: true,
    background: Color(0xFF000000),
    cell: Color(0xFF000000),
    elevated: Color(0xFF000000),
    label: Color(0xFFFFFFFF),
    secondaryLabel: Color(0xFFDDDDDD),
    tertiaryLabel: Color(0xFFAAAAAA),
    separator: Color(0xFFFFFFFF),
    fill: Color(0xFF222222),
    accent: Color(0xFFFFFFFF),
    onAccent: Color(0xFF000000),
    destructive: Color(0xFFFFFFFF),
    bar: Color(0xFF000000),
  );

  bool get eink => identical(this, einkLight) || identical(this, einkDark);

  static Palette of(BuildContext context) =>
      Theme.of(context).extension<PaletteExtension>()?.palette ??
      (Theme.of(context).brightness == Brightness.dark ? darkMode : light);
}

/// Carries the [Palette] through the Material theme.
class PaletteExtension extends ThemeExtension<PaletteExtension> {
  const PaletteExtension(this.palette);
  final Palette palette;
  @override
  PaletteExtension copyWith({Palette? palette}) =>
      PaletteExtension(palette ?? this.palette);
  @override
  PaletteExtension lerp(PaletteExtension? other, double t) =>
      t < .5 ? this : (other ?? this);
}
