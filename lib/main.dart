import 'package:flutter/material.dart';
import 'src/terminal_view.dart';

void main() {
  runApp(const FlutterGhosttyApp());
}

class FlutterGhosttyApp extends StatelessWidget {
  const FlutterGhosttyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Ghostty',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const Scaffold(
        body: TerminalView(
          fontSize: 14.0,
          fontFamily: 'monospace',
          padding: 4.0,
        ),
      ),
    );
  }
}
