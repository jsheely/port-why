import 'package:flutter/material.dart';

import 'data/favorites_store.dart';
import 'data/port_repository.dart';
import 'ui/ambient.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';
import 'ui/title_bar.dart';

class PortWhyApp extends StatelessWidget {
  const PortWhyApp({
    super.key,
    required this.repository,
    this.favorites,
    this.drawsWindowButtons,
  });

  final PortRepository repository;

  /// Where favourite ports are kept. Left out, they last only for this run.
  final FavoritesStore? favorites;

  /// Whether the window's buttons are the app's to draw. Left out, they are
  /// on Windows alone; macOS and Linux keep their own title bar.
  final bool? drawsWindowButtons;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Port Why',
      debugShowCheckedModeBanner: false,
      // Neon needs the dark: there is no light theme.
      theme: buildTheme(),
      // Above the navigator, so dialogs keep time with the page beneath them.
      builder: (context, child) => Ambient(
        child: WindowFrame(drawsButtons: drawsWindowButtons, child: child!),
      ),
      home: HomePage(repository: repository, favorites: favorites),
    );
  }
}
