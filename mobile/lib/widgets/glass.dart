import 'package:flutter/material.dart';
import '../theme.dart';
import 'draggable_fab.dart';

/// Every top-level screen's outer shell. The body sits on a soft indigo-purple-pink gradient wash
/// (careloopBgGradient) — Scaffold itself can only hold a flat backgroundColor, so the gradient is
/// painted as its own full-bleed layer underneath a transparent Scaffold. The chrome around it
/// (GlassAppBar/GlassBottomBar below) stays solid white, painting over the gradient at the edges.
/// Use this instead of a bare Scaffold for any screen that owns its own navigation (i.e. not a tab
/// inside an already-wrapped screen).
///
/// The FAB (when given one) is deliberately NOT passed to Scaffold's own floatingActionButton
/// slot — it's rendered as a draggable overlay instead, so "Ask me" can be moved anywhere on
/// screen rather than sitting fixed in one corner.
class GlassScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final String fabStorageKey;
  const GlassScaffold({super.key, this.appBar, required this.body, this.floatingActionButton, this.bottomNavigationBar, this.fabStorageKey = 'default'});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      const Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: careloopBgGradient)),
        ),
      ),
      Scaffold(
        backgroundColor: Colors.transparent,
        appBar: appBar,
        body: body,
        bottomNavigationBar: bottomNavigationBar,
      ),
      if (floatingActionButton != null) Positioned.fill(child: DraggableFab(storageKey: fabStorageKey, child: floatingActionButton!)),
    ]);
  }
}

/// A solid premium sky-blue app bar, dark navy text/icons, a soft hairline at the bottom edge.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;

  const GlassAppBar({super.key, this.title, this.actions, this.leading, this.bottom});

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: careloopPanelFill,
        border: Border(bottom: BorderSide(color: careloopPanelBorder, width: 1)),
      ),
      child: AppBar(
        title: title,
        actions: actions,
        leading: leading,
        bottom: bottom,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }
}

/// A solid premium sky-blue bottom navigation bar — same treatment as GlassAppBar, top hairline
/// instead of bottom.
class GlassBottomBar extends StatelessWidget {
  final Widget child;
  const GlassBottomBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: careloopPanelFill,
        border: Border(top: BorderSide(color: careloopPanelBorder, width: 1)),
      ),
      child: SafeArea(top: false, child: child),
    );
  }
}

/// A solid premium sky-blue panel — the building block for the member profile screen's left-nav
/// and right-detail slabs (and anywhere else that needs a floating panel over the white page).
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  const GlassPanel({super.key, required this.child, this.padding = const EdgeInsets.all(12), this.radius = careloopRadiusLg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: careloopPanelFill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: careloopPanelBorder),
        boxShadow: careloopPanelShadow,
      ),
      child: child,
    );
  }
}
