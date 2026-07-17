import 'package:fl_nodes/fl_nodes.dart';
import 'package:flutter/material.dart';

// Namespace for static style helpers.
// ignore: avoid_classes_with_only_static_members
/// Vyuh Image Effects Pipeline visual language for the example.
abstract final class VyuhEditorTheme {
  static const Color canvas = Color(0xFFFAFAFA);
  static const Color nodeBg = Colors.white;
  static const Color nodeBgSelected = Color(0xFFFAFAFA);
  static const Color nodeBgHover = Color(0xFFF8FAFC);
  static const Color border = Color(0xFFCBD5E1);
  static const Color borderSelected = Color(0xFF818CF8);
  static const Color borderHover = Color(0xFFA5B4FC);
  static const Color link = Color(0xFFD1D5DB);
  static const Color portIdle = Color(0xFFD1D5DB);
  static const Color dataAccent = Color(0xFF60A5FA);
  static const Color controlAccent = Color(0xFF34D399);
  static const Color valueAccent = Color(0xFFF59E0B);
  static const Color generatorAccent = Color(0xFF60A5FA);
  static const Color logicAccent = Color(0xFFF472B6);
  static const Color mathAccent = Color(0xFF34D399);
  static const Color flowAccent = Color(0xFF818CF8);
  static const Color ioAccent = Color(0xFFA78BFA);
  static const Color fieldBg = Color(0xFFF8FAFC);
  static const Color fieldBorder = Color(0xFFE2E8F0);
  static const Color text = Color(0xFF334155);

  static const FlFieldStyle fieldStyle = FlFieldStyle(
    decoration: BoxDecoration(
      color: fieldBg,
      borderRadius: BorderRadius.all(Radius.circular(8)),
      border: Border.fromBorderSide(
        BorderSide(color: fieldBorder),
      ),
    ),
    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  );

  static FlNodesStyle editorStyle({bool showGrid = true}) => FlNodesStyle(
        decoration: const BoxDecoration(color: canvas),
        gridStyle: const FlGridStyle.dots().copyWith(showGrid: showGrid),
        highlightAreaStyle: const FlHighlightAreaStyle(
          color: Color(0x26818CF8),
          borderWidth: 1,
          borderColor: Color(0xB3818CF8),
          borderDrawMode: FlLineDrawMode.solid,
        ),
        nodesShadow: null,
      );

  static ThemeData materialTheme() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: canvas,
        colorScheme: ColorScheme.fromSeed(
          seedColor: borderSelected,
          brightness: Brightness.light,
          surface: Colors.white,
        ),
      );
}
