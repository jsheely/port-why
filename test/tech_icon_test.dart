import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:port_why/src/ui/tech_icon.dart';
import 'package:port_why/src/ui/theme.dart';

void main() {
  test('every glyph is legible on its tile', () {
    final tooFaint = <String>[
      for (final MapEntry(:key, :value) in techGlyphs.entries)
        if (glyphContrast(legibleBrandColor(value.color, cyberScheme), cyberScheme) <
            minGlyphContrast)
          key,
    ];
    expect(tooFaint, isEmpty);
  });

  test('a brand colour that already reads is left exactly as it is', () {
    const vueGreen = Color(0xff4fc08d);
    expect(legibleBrandColor(vueGreen, cyberScheme), vueGreen);
  });

  test('a dark brand colour keeps its hue but is lightened', () {
    const dotnetPurple = Color(0xff512bd4);
    final shown = legibleBrandColor(dotnetPurple, cyberScheme);
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
    expect(
      legibleBrandColor(const Color(0xff000000), cyberScheme),
      cyberScheme.onSurface,
    );
  });
}
