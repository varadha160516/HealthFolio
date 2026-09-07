import 'package:flutter/material.dart';
import '../theme.dart';

/// The bold section heading that sits above a card, directly on the flat page background — plain
/// dark ink now, no shadow needed since the backdrop is flat and light, not a vivid gradient.
/// Never the small uppercase eyebrow treatment, that's reserved for genuinely small meta text
/// (see careloopEyebrow in theme.dart).
class SectionCaption extends StatelessWidget {
  final String title;
  final IconData? icon;
  const SectionCaption(this.title, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Row(children: [
        if (icon != null) ...[Icon(icon, size: 16, color: careloopAccent), const SizedBox(width: 8)],
        // Expanded so a long title wraps to a second line instead of being clipped by the row's
        // available width (an un-constrained Text here silently overflowed past the screen edge).
        Expanded(child: Text(title, style: careloopSectionHeading())),
      ]),
    );
  }
}

/// A card — neutral white fill by default, hairline border, subtle shadow lift. Pass [color] to
/// use one of the named pastel surfaces instead (theme.dart's careloopLavender/Periwinkle/Blush/
/// Cream/Lilac) for a card that should visually stand out as its own kind of information.
class SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final IconData? icon;
  final Color? color;
  const SectionCard({super.key, this.title, required this.child, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) SectionCaption(title!, icon: icon),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: color ?? careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
            child: child,
          ),
        ],
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  final String text;
  final bool info;
  const InfoBanner(this.text, {super.key, this.info = false});

  @override
  Widget build(BuildContext context) {
    final fg = info ? careloopInfo : careloopWarning;
    final bg = info ? careloopNewBg : careloopWarningBg;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(careloopRadiusMd)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(info ? Icons.info_rounded : Icons.warning_rounded, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: fg, fontSize: 13.5, height: 1.35, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

class LoadingCenter extends StatelessWidget {
  const LoadingCenter({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: careloopPrimary)));
}
