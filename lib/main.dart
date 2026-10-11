import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/data/port_repository.dart';

void main() {
  runApp(PortWhyApp(repository: createPortRepository()));
}
