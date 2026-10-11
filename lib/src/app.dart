import 'package:flutter/material.dart';

import 'data/favorites_store.dart';
import 'data/port_repository.dart';
import 'ui/ambient.dart';
import 'ui/exp_bench.dart'; // EXPERIMENT
import 'ui/home_page.dart';
import 'ui/theme.dart';
import 'ui/title_bar.dart';

class PortWhyApp extends StatelessWidget {
  const PortWhyApp({super.key, required this.repository, this.favorites});

  final PortRepository repository;

  /// Where favourite ports are kept. Left out, they last only for this run.
  final FavoritesStore? favorites;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Port Why',
      debugShowCheckedModeBanner: false,
      // Neon needs the dark: there is no light theme.
      theme: buildTheme(),
      // Above the navigator, so dialogs keep time with the page beneath them.
      builder: (context, child) => Ambient(child: WindowFrame(child: child!)),
      home: benchKind != null ? BenchPage(kind: benchKind!) : HomePage(repository: repository, favorites: favorites), // EXPERIMENT
    );
  }
}
