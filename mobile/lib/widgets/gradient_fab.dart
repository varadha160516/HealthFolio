import 'package:flutter/material.dart';
import '../theme.dart';

/// A FloatingActionButton.extended look-alike, but with the real brand gradient the reference
/// shows — FloatingActionButton itself only accepts a flat backgroundColor, so this hand-builds
/// the same pill shape (Material + InkWell for the ripple, rounded gradient Container) instead.
class GradientFab extends StatelessWidget {
  final String tooltip;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  const GradientFab({super.key, required this.tooltip, required this.label, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(careloopRadiusPill),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: careloopPrimaryGradient),
            borderRadius: BorderRadius.circular(careloopRadiusPill),
            boxShadow: const [BoxShadow(color: Color(0x556D5DF6), blurRadius: 18, offset: Offset(0, 8))],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(careloopRadiusPill),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
