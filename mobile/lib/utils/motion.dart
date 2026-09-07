import 'package:flutter/material.dart';

/// The app's one motion language — a single consistent push transition and a single consistent
/// list-entrance animation, used everywhere rather than each screen inventing (or more often,
/// not bothering with) its own. An app with zero motion cannot read as premium regardless of how
/// good any single static screen looks; consistency here matters more than any one effect being
/// clever.
///
/// Replaces `Navigator.push(context, MaterialPageRoute(builder: ...))` with a route that slides
/// in from the right while fading, at a restrained duration/curve — deliberately closer to a
/// native platform push than an M3-textbook one, since the rest of the app already leans iOS.
Route<T> pushRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Fades and lifts a list/grid item into place with a small per-index delay, so a screen's
/// content arrives as a deliberate cascade rather than snapping in all at once. Delay is capped
/// (see [maxStaggeredIndex]) so a long list doesn't make the last few items wait absurdly long.
const maxStaggeredIndex = 10;

class FadeInUp extends StatefulWidget {
  final Widget child;
  final int index;
  const FadeInUp({super.key, required this.child, this.index = 0});

  @override
  State<FadeInUp> createState() => _FadeInUpState();
}

class _FadeInUpState extends State<FadeInUp> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    final delayIndex = widget.index > maxStaggeredIndex ? maxStaggeredIndex : widget.index;
    Future.delayed(Duration(milliseconds: 35 * delayIndex), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _fade, child: SlideTransition(position: _slide, child: widget.child));
  }
}
