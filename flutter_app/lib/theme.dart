import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'ui/tokens.dart';

export 'ui/tokens.dart' show Palette;

// The original code-drawn jacket keeps its own print-inspired palette.
const ink = Color(0xFF193E36);
const paper = Color(0xFFF6F5EF);
const muted = Color(0xFF727A72);

ThemeData novelTheme(Brightness brightness, {bool ereader = false}) {
  final dark = brightness == Brightness.dark;
  final p = ereader
      ? (dark ? Palette.einkDark : Palette.einkLight)
      : (dark ? Palette.darkMode : Palette.light);
  final colors =
      ColorScheme.fromSeed(
        seedColor: p.accent,
        brightness: brightness,
        dynamicSchemeVariant: ereader
            ? DynamicSchemeVariant.monochrome
            : DynamicSchemeVariant.tonalSpot,
      ).copyWith(
        primary: p.accent,
        onPrimary: p.onAccent,
        surface: p.background,
        onSurface: p.label,
        onSurfaceVariant: p.secondaryLabel,
        surfaceContainerLowest: p.cell,
        surfaceContainerLow: p.cell,
        surfaceContainer: p.cell,
        surfaceContainerHigh: p.elevated,
        surfaceContainerHighest: p.elevated,
        outline: p.separator,
        outlineVariant: p.separator,
        error: p.destructive,
        secondaryContainer: p.fill,
        onSecondaryContainer: p.label,
      );
  TextStyle t(TextStyle s) => s.copyWith(color: p.label);
  final text = TextTheme(
    displayLarge: t(TextStyles.largeTitle),
    displayMedium: t(TextStyles.largeTitle),
    displaySmall: t(TextStyles.title1),
    headlineLarge: t(TextStyles.largeTitle),
    headlineMedium: t(TextStyles.title1),
    headlineSmall: t(TextStyles.title2),
    titleLarge: t(TextStyles.title3),
    titleMedium: t(TextStyles.headline),
    titleSmall: t(TextStyles.subheadline.copyWith(fontWeight: FontWeight.w600)),
    bodyLarge: t(TextStyles.body),
    bodyMedium: t(TextStyles.subheadline),
    bodySmall: TextStyles.footnote.copyWith(color: p.secondaryLabel),
    labelLarge: t(TextStyles.headline),
    labelMedium: TextStyles.footnote.copyWith(color: p.secondaryLabel),
    labelSmall: TextStyles.caption2.copyWith(color: p.secondaryLabel),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colors,
    fontFamily: 'DM Sans',
    textTheme: text,
    extensions: [PaletteExtension(p)],
    // Large-title navigation bars and other Cupertino widgets use the same
    // font and colors as the rest of the app.
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: p.accent,
      barBackgroundColor: p.bar,
      scaffoldBackgroundColor: p.background,
      textTheme: CupertinoTextThemeData(
        primaryColor: p.accent,
        textStyle: t(TextStyles.body),
        actionTextStyle: TextStyles.body.copyWith(color: p.accent),
        navTitleTextStyle: t(TextStyles.headline),
        navLargeTitleTextStyle: t(TextStyles.largeTitle),
        navActionTextStyle: TextStyles.body.copyWith(color: p.accent),
      ),
    ),
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const Icon(CupertinoIcons.back),
      closeButtonIconBuilder: (_) => const Icon(CupertinoIcons.xmark),
    ),
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    dividerColor: p.separator,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    // Apple-style navigation everywhere, with swipe-back; none on e-ink.
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final platform in TargetPlatform.values)
          platform: ereader
              ? const _StillPageTransition()
              : const CupertinoPageTransitionsBuilder(),
      },
    ),
    splashFactory: ereader ? NoSplash.splashFactory : InkRipple.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.accent,
      titleTextStyle: t(TextStyles.headline),
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: p.accent),
      actionsIconTheme: IconThemeData(color: p.accent),
    ),
    iconTheme: IconThemeData(color: p.accent),
    listTileTheme: ListTileThemeData(
      iconColor: p.accent,
      titleTextStyle: t(TextStyles.body),
      subtitleTextStyle: TextStyles.subheadline.copyWith(
        color: p.secondaryLabel,
      ),
      minTileHeight: minTarget + 8,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.fill,
      hintStyle: TextStyles.body.copyWith(color: p.secondaryLabel),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.small + 2),
        borderSide: ereader ? BorderSide(color: p.separator) : BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        minimumSize: const Size(minTarget, minTarget),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: const StadiumBorder(),
        textStyle: TextStyles.headline,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.accent,
        backgroundColor: p.fill,
        side: ereader ? BorderSide(color: p.separator) : BorderSide.none,
        minimumSize: const Size(minTarget, minTarget),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: const StadiumBorder(),
        textStyle: TextStyles.headline,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.accent,
        minimumSize: const Size(minTarget, minTarget),
        textStyle: TextStyles.body,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: p.accent,
        minimumSize: const Size(minTarget, minTarget),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.fill,
      selectedColor: p.accent,
      secondarySelectedColor: p.accent,
      labelStyle: t(TextStyles.subheadline),
      secondaryLabelStyle: TextStyles.subheadline.copyWith(color: p.onAccent),
      checkmarkColor: p.onAccent,
      side: ereader ? BorderSide(color: p.separator) : BorderSide.none,
      shape: const StadiumBorder(),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: p.fill,
        selectedBackgroundColor: p.elevated,
        selectedForegroundColor: p.label,
        foregroundColor: p.label,
        side: BorderSide(color: p.fill),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.accent,
      inactiveTrackColor: p.fill,
      thumbColor: ereader ? p.label : Colors.white,
      overlayColor: p.accent.withValues(alpha: .12),
      trackHeight: 4,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.accent,
      linearTrackColor: p.fill,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: p.cell,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.section),
        side: ereader ? BorderSide(color: p.separator) : BorderSide.none,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.elevated,
      modalBackgroundColor: p.elevated,
      dragHandleColor: p.tertiaryLabel,
      dragHandleSize: const Size(36, 5),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.elevated,
      titleTextStyle: t(TextStyles.headline),
      contentTextStyle: t(TextStyles.subheadline),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.section),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.elevated,
      textStyle: t(TextStyles.body),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.small + 4),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? p.elevated : const Color(0xFF2C2C2E),
      contentTextStyle: TextStyles.subheadline.copyWith(color: Colors.white),
      shape: const StadiumBorder(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.bar,
      indicatorColor: Colors.transparent,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: p.background,
      indicatorColor: p.fill,
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : p.fill,
      ),
    ),
  );
}

class _StillPageTransition extends PageTransitionsBuilder {
  const _StillPageTransition();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
