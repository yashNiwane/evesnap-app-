import 'package:flutter/material.dart';

class EvePalette {
  const EvePalette._();

  static const ink = Color(0xFF05070B);
  static const night = Color(0xFF080A0E);
  static const coal = Color(0xFF10141B);
  static const smoke = Color(0xFF151B25);
  static const toasted = Color(0xFF0D121A);
  static const line = Color(0xFF202734);
  static const bone = Color(0xFFE7EBF2);
  static const parchment = Color(0xFFD7DEE9);
  static const muted = Color(0xFF96A0B2);
  static const amber = Color(0xFFBFD8FF);
  static const ember = Color(0xFF7F93B3);
  static const sage = Color(0xFF798396);
  static const moss = Color(0xFF3A4557);
  static const wine = Color(0xFF151B25);

  static const pageGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ink, night, Color(0xFF0D121A)],
  );

  static const cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF121B2A), Color(0xFF0E1522)],
  );

  static const warmGlow = BoxShadow(
    color: Color(0x33131924),
    blurRadius: 24,
    offset: Offset(0, 14),
  );
}
