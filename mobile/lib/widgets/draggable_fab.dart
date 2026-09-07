import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps a floating action button so it can be dragged anywhere on screen — "Ask me" shouldn't
/// be stuck in one fixed spot (see the earlier fix for it overlapping list content when it WAS
/// fixed). Position is stored as a fraction of the screen size, not raw pixels, so it stays
/// sensible across device sizes/rotations, and persisted under [storageKey] so it stays where the
/// user last left it rather than resetting every time they navigate back to this screen.
class DraggableFab extends StatefulWidget {
  final Widget child;
  final String storageKey;
  const DraggableFab({super.key, required this.child, required this.storageKey});

  @override
  State<DraggableFab> createState() => _DraggableFabState();
}

class _DraggableFabState extends State<DraggableFab> {
  static const _margin = 16.0;
  // A reasonable guess for an extended (icon + label) FAB before the real size is measured —
  // only matters for the very first frame, so a slightly-off default here never causes a visible
  // jump (the drag bounds just tighten slightly once _measuredSize updates).
  Size _measuredSize = const Size(150, 56);
  final _childKey = GlobalKey();

  Offset? _fraction; // null until a saved position has loaded (or the user has moved it)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble('fab_pos_${widget.storageKey}_x');
    final y = prefs.getDouble('fab_pos_${widget.storageKey}_y');
    if (mounted && x != null && y != null) setState(() => _fraction = Offset(x, y));
  }

  Future<void> _save() async {
    final f = _fraction;
    if (f == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fab_pos_${widget.storageKey}_x', f.dx);
    await prefs.setDouble('fab_pos_${widget.storageKey}_y', f.dy);
  }

  /// The button's real size depends on its content (an extended FAB's label text isn't a fixed
  /// 56x56 square like a plain icon FAB), so it's measured after layout rather than assumed —
  /// getting this wrong would let a wide "Ask me" button clip past the screen edge.
  void _measure() {
    final box = _childKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    if (box.size != _measuredSize && mounted) setState(() => _measuredSize = box.size);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return LayoutBuilder(builder: (context, constraints) {
      final maxX = constraints.maxWidth - _measuredSize.width - _margin;
      final maxY = constraints.maxHeight - _measuredSize.height - _margin;
      // Default lands exactly where a normal Scaffold FAB sits (bottom-right) so a first-time
      // user sees no visible change until they actually drag it.
      final position = _fraction == null
          ? Offset(maxX, maxY)
          : Offset((_fraction!.dx * constraints.maxWidth).clamp(_margin, maxX), (_fraction!.dy * constraints.maxHeight).clamp(_margin, maxY));

      return Stack(children: [
        Positioned(
          left: position.dx,
          top: position.dy,
          child: GestureDetector(
            onPanUpdate: (details) {
              final next = Offset((position.dx + details.delta.dx).clamp(_margin, maxX), (position.dy + details.delta.dy).clamp(_margin, maxY));
              setState(() => _fraction = Offset(next.dx / constraints.maxWidth, next.dy / constraints.maxHeight));
            },
            onPanEnd: (_) => _save(),
            child: KeyedSubtree(key: _childKey, child: widget.child),
          ),
        ),
      ]);
    });
  }
}
