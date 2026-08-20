import 'package:flutter/material.dart';

// ============================================================================
// TEMPORARY dev aid — shows the current screen's filename in a thin bar at
// the very bottom of the screen, so it's obvious which file to open when
// looking at something on-device. Add `bottomNavigationBar:
// const DebugFileLabel(fileName: 'screen_name.dart')` to any Scaffold.
//
// Safe to leave in during development; remove all usages (and this file)
// before shipping to the Play Store.
// ============================================================================

class DebugFileLabel extends StatelessWidget {
  final String fileName;

  const DebugFileLabel({super.key, required this.fileName});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        color: Colors.black87,
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(
          fileName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.limeAccent,
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}