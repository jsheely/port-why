import 'package:flutter/material.dart';

import '../models.dart';
import 'soft_edge.dart';

/// The neon palette. Everything on screen is one of these over near-black.
abstract final class Neon {
  static const cyan = Color(0xff19e3ff);
  static const pink = Color(0xffff2e7e);
  static const violet = Color(0xffa573ff);
  static const yellow = Color(0xfffcee0a);
  static const green = Color(0xff35ff9f);

  /// The night behind the glass, top and bottom.
  static const abyss = Color(0xff04050d);
  static const dusk = Color(0xff0c0920);

  /// What tints a pane of glass before any light reaches it.
  static const smoke = Color(0xff0a0e22);

  /// The colour a port is drawn in, by the kind of thing holding it.
  static Color of(PortCategory category) => switch (category) {
    PortCategory.project => cyan,
    PortCategory.app => violet,
    PortCategory.system => yellow,
  };
}

/// Both faces ship with Windows. Bahnschrift is the DIN of road signs and
/// instrument panels, which is the look wanted here.
const displayFont = 'Bahnschrift';
const monoFont = 'Cascadia Mono';

/// Port numbers, paths, commands and readouts.
const mono = TextStyle(
  fontFamily: monoFont,
  // Windows 10 has no Cascadia.
  fontFamilyFallback: ['Consolas'],
);

/// The small capitals that caption a readout.
const caption = TextStyle(
  fontSize: 10.5,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.5,
  height: 1.2,
);

/// A neon tube: the colour itself, and the light it throws.
List<Shadow> neonGlow(Color color, {double spread = 10, double alpha = 0.7}) => [
  Shadow(color: color.withValues(alpha: alpha), blurRadius: spread),
];

/// A recess cut into a pane of glass, for fields and switch tracks.
BoxDecoration well({double radius = 12, Color? edge, List<BoxShadow>? glow}) =>
    BoxDecoration(
      color: Colors.black.withValues(alpha: 0.32),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: edge ?? Colors.white.withValues(alpha: 0.09)),
      boxShadow: glow,
    );

const cyberScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Neon.cyan,
  onPrimary: Color(0xff00171c),
  primaryContainer: Color(0xff06323d),
  onPrimaryContainer: Color(0xffa9f5ff),
  secondary: Neon.violet,
  onSecondary: Color(0xff14082f),
  secondaryContainer: Color(0xff2a1b57),
  onSecondaryContainer: Color(0xffe2d6ff),
  tertiary: Neon.yellow,
  onTertiary: Color(0xff1d1b00),
  error: Neon.pink,
  onError: Color(0xff25000d),
  surface: Color(0xff070817),
  onSurface: Color(0xffe9f0ff),
  onSurfaceVariant: Color(0xff909dc6),
  outline: Color(0xff4b5784),
  outlineVariant: Color(0xff232b4d),
  surfaceContainerLowest: Neon.abyss,
  // Roughly what a pane of glass comes out as over the backdrop: icons are
  // checked for contrast against this.
  surfaceContainerLow: Color(0xff0d1024),
  surfaceContainer: Color(0xff111530),
  surfaceContainerHigh: Color(0xff161b3b),
  surfaceContainerHighest: Color(0xff1c2247),
);

ThemeData buildTheme() {
  const scheme = cyberScheme;
  // Corners are cut, not rounded, wherever something is not made of glass.
  const cut = CutBorder();
  final readout = mono.copyWith(fontSize: 12, color: scheme.onSurface);

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: Neon.abyss,
    fontFamily: displayFont,
    fontFamilyFallback: const ['Segoe UI'],
    visualDensity: VisualDensity.compact,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: Neon.cyan,
      selectionColor: Neon.cyan.withValues(alpha: 0.28),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyle: readout.copyWith(fontSize: 11.5),
      decoration: ShapeDecoration(
        color: Neon.smoke.withValues(alpha: 0.96),
        shape: cut.copyWith(
          side: BorderSide(color: Neon.cyan.withValues(alpha: 0.45)),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      width: 560,
      elevation: 0,
      backgroundColor: Neon.smoke.withValues(alpha: 0.96),
      contentTextStyle: readout.copyWith(height: 1.35),
      shape: cut.copyWith(
        cut: 9,
        side: BorderSide(color: Neon.cyan.withValues(alpha: 0.6)),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(5),
      radius: const Radius.circular(3),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => Neon.cyan.withValues(
          alpha: states.any(_engaged.contains) ? 0.75 : 0.3,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Neon.cyan, shape: cut),
    ),
    filledButtonTheme: FilledButtonThemeData(style: neonButton(Neon.cyan)),
  );
}

const _engaged = {WidgetState.hovered, WidgetState.dragged, WidgetState.pressed};

/// A button that is an outline of light with a faint fill, rather than a slab
/// of colour.
ButtonStyle neonButton(Color color) => FilledButton.styleFrom(
  backgroundColor: color.withValues(alpha: 0.14),
  foregroundColor: color,
  overlayColor: color,
  side: BorderSide(color: color.withValues(alpha: 0.7)),
  shape: const CutBorder(),
);
