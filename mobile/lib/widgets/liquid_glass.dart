import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme.dart';

/// A frosted-glass panel — translucent, blurring whatever sits behind it (LiquidBlobBackground,
/// typically). BackdropFilter only blurs pixels already painted behind it in the same Stack, so
/// this is meaningless without something colorful underneath — see LiquidBlobBackground below.
/// Clipped to its own rounded shape, since an unclipped BackdropFilter blurs the whole layer.
class GlassPane extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color tint;
  final double tintOpacity;
  const GlassPane({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = careloopRadiusLg,
    this.tint = Colors.white,
    this.tintOpacity = 0.52,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: tintOpacity),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
            boxShadow: [
              BoxShadow(color: const Color(0x38503CB4), blurRadius: 24, offset: const Offset(0, 10)),
              BoxShadow(color: Colors.white.withValues(alpha: 0.8), blurRadius: 0, spreadRadius: -1, offset: const Offset(0, 1)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Soft, oversized color blobs positioned behind the glass content — purely decorative, and load-
/// bearing for the glass effect: without something behind the panels to blur, BackdropFilter has
/// nothing to do and the panels just look like faded gray boxes. Sized/placed to roughly track a
/// tall scrolling screen; wrap in a Positioned.fill behind the scroll content.
class LiquidBlobBackground extends StatelessWidget {
  const LiquidBlobBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      _blob(top: -60, left: -50, size: 220, color: const Color(0xFF9D5FEA), opacity: 0.5),
      _blob(top: 60, right: -70, size: 240, color: const Color(0xFFE86BC4), opacity: 0.4),
      _blob(top: 380, left: -60, size: 220, color: const Color(0xFF6D5DF6), opacity: 0.38),
      _blob(top: 640, right: -50, size: 210, color: const Color(0xFF14B8A6), opacity: 0.3),
      _blob(top: 900, left: 20, size: 200, color: const Color(0xFFE8863C), opacity: 0.26),
    ]);
  }

  Widget _blob({double? top, double? left, double? right, required double size, required Color color, required double opacity}) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
