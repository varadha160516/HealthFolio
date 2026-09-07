import 'package:flutter/material.dart';

/// Muted, coordinated with the rest of the app's palette — no bright/saturated colors. Keyed by
/// family role rather than a hash of the person's name: a hash can collide badly across a small
/// family (it did — 4 of 6 members landed on the same color by chance), which reads as broken,
/// not designed. Keying by role instead guarantees variety in the common case and is actually
/// meaningful — the same role gets the same color everywhere in the app (dashboard, profile hero).
const _roleColors = <String, Color>{
  'self': Color(0xFF3E6D63), // brand teal
  'spouse': Color(0xFFAD6E58), // muted terracotta
  'parent': Color(0xFF4C7690), // muted slate blue
  'child': Color(0xFF7A6A8A), // muted plum
  'other': Color(0xFF9C7B3E), // muted ochre
};
const _fallbackRoleColor = Color(0xFF5B7F5E); // muted sage — unrecognized relationship strings

Color colorForRelationship(String? relationship) => _roleColors[relationship] ?? _fallbackRoleColor;
