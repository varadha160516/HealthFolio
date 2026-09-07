import 'package:flutter/material.dart';
import '../theme.dart';

/// "Emptiness is an invitation to act, not a mood" — a short line plus the relevant primary
/// action. A glass icon badge is back (unlike the flat system this replaced, which banned all
/// empty-state graphics) — a plain icon in a soft frosted circle isn't decorative illustration,
/// just a small visual anchor consistent with the rest of the glass surface language.
class EmptyState extends StatelessWidget {
  final String message;
  final IconData? icon;
  final Widget? action;
  const EmptyState({super.key, required this.message, this.icon, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: careloopSurface,
                  border: careloopCardBorder,
                  boxShadow: careloopCardShadow,
                ),
                child: Icon(icon, size: 28, color: careloopAccent),
              ),
              const SizedBox(height: 18),
            ],
            Text(message, textAlign: TextAlign.center, style: careloopPageTitle(color: careloopMuted).copyWith(fontSize: careloopTypeTitle)),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
