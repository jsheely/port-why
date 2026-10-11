import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:port_why/src/ui/tech_icon.dart';

void main() {
  // The same seed the app themes itself with.
  ColorScheme scheme(Brightness brightness) => ColorScheme.fromSeed(
    seedColor: const Color(0xff3d7dff),
    brightness: brightness,
  );

  for (final brightness in Brightness.values) {
    test('every glyph is legible on its tile in ${brightness.name} mode', () {
      final colors = scheme(brightness);
      final tooFaint = <String>[
        for (final MapEntry(:key, :value) in techGlyphs.entries)
          if (glyphContrast(legibleBrandColor(value.color, colors), colors) <
              minGlyphContrast)
            key,
      ];
      expect(tooFaint, isEmpty);
    });
  }

  test('a brand colour that already reads is left exactly as it is', () {
    const vueGreen = Color(0xff4fc08d);
    expect(legibleBrandColor(vueGreen, scheme(Brightness.dark)), vueGreen);
  });

  test('a dark brand colour keeps its hue but is lightened in dark mode', () {
    const dotnetPurple = Color(0xff512bd4);
    final shown = legibleBrandColor(dotnetPurple, scheme(Brightness.dark));
    expect(shown, isNot(dotnetPurple));
    expect(
      HSLColor.fromColor(shown).hue,
      closeTo(HSLColor.fromColor(dotnetPurple).hue, 1),
    );
    expect(
      HSLColor.fromColor(shown).lightness,
      greaterThan(HSLColor.fromColor(dotnetPurple).lightness),
    );
  });

  test('black marks use the text colour instead of vanishing', () {
    final dark = scheme(Brightness.dark);
    expect(legibleBrandColor(const Color(0xff000000), dark), dark.onSurface);
  });
}
