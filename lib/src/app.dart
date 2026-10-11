import 'package:flutter/material.dart';

import 'data/port_repository.dart';
import 'ui/home_page.dart';

class PortWhyApp extends StatelessWidget {
  const PortWhyApp({super.key, required this.repository});

  final PortRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Port Why',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: HomePage(repository: repository),
    );
  }

  static ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff3d7dff),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      visualDensity: VisualDensity.compact,
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 450),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        width: 560,
      ),
    );
  }
}
