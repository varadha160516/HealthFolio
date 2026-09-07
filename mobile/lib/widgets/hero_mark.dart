import 'package:flutter/material.dart';
import '../theme.dart';

/// The brand mark — heart + cross + leaf, direct on the background (no circle badge). Shared by
/// the first-time login screen and the PIN/Face ID lock screen so both actually show the same
/// mark from the reference mockup, rather than each screen drawing its own approximation.
class HeroMark extends StatelessWidget {
  final double size;
  const HeroMark({super.key, this.size = 70});

  @override
  Widget build(BuildContext context) {
    final scale = size / 70;
    return SizedBox(
      width: size,
      height: 66 * scale,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.favorite_rounded, size: 68 * scale, color: careloopPrimary),
          Padding(
            padding: EdgeInsets.only(bottom: 8 * scale),
            child: SizedBox(
              width: 13 * scale,
              height: 13 * scale,
              child: Stack(alignment: Alignment.center, children: [
                _CrossBar(width: 3.5 * scale, height: 13 * scale),
                _CrossBar(width: 13 * scale, height: 3.5 * scale),
              ]),
            ),
          ),
          Positioned(bottom: -2 * scale, right: 4 * scale, child: Icon(Icons.eco_rounded, size: 20 * scale, color: careloopSuccess)),
        ],
      ),
    );
  }
}

class _CrossBar extends StatelessWidget {
  final double width;
  final double height;
  const _CrossBar({required this.width, required this.height});
  @override
  Widget build(BuildContext context) => Container(width: width, height: height, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(width < height ? width / 2 : height / 2)));
}

/// Faint decorative line-art (clipboard, shield, heartbeat, leaf) scattered behind login/lock
/// screen content, echoing the reference mockup's background illustration. Purely decorative —
/// wrap content in a Stack with this as the first child.
class DecorativeBackdrop extends StatelessWidget {
  const DecorativeBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned(
        top: 46,
        left: 18,
        child: Opacity(
          opacity: 0.09,
          child: Icon(Icons.assignment_outlined, size: 70, color: careloopPrimary),
        ),
      ),
      Positioned(
        top: 56,
        right: 20,
        child: Opacity(
          opacity: 0.1,
          child: Icon(Icons.shield_outlined, size: 60, color: careloopInfo),
        ),
      ),
      Positioned(
        top: 150,
        left: 26,
        child: Opacity(
          opacity: 0.09,
          child: Icon(Icons.monitor_heart_outlined, size: 46, color: careloopSuccess),
        ),
      ),
      Positioned(
        top: 140,
        right: 14,
        child: Opacity(
          opacity: 0.1,
          child: Icon(Icons.eco_outlined, size: 50, color: careloopSuccess),
        ),
      ),
    ]);
  }
}
