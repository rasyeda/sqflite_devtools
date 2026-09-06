import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

import 'src/explorer.dart';

void main() {
  runApp(const SqfliteDevToolsExtension());
}

class SqfliteDevToolsExtension extends StatelessWidget {
  const SqfliteDevToolsExtension({super.key});

  @override
  Widget build(BuildContext context) {
    // [DevToolsExtension] wires up the theme, the service manager and the
    // connection to the DevTools window around our own widget tree.
    return const DevToolsExtension(child: ExplorerScreen());
  }
}
