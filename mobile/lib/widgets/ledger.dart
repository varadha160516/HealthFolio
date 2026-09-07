import 'package:flutter/material.dart';
import '../theme.dart';
import '../utils/motion.dart';
import 'section_card.dart';

/// The signature component (design system Section 3.3) — build once, reuse everywhere data is
/// listed: lab results, medications, documents, timeline, audit logs, the payer population table.
/// Left-aligned label, right-aligned trailing content, a hairline rule between rows (no zebra
/// striping, no cell borders, no card-per-row). This one recurring pattern is what should make
/// CareLoop visually recognizable at a glance — a bank statement or passport register's line
/// item, not a generic list tile.
class LedgerRow extends StatelessWidget {
  final IconData? leadingIcon;
  final String label;
  final String? sublabel;
  final Widget trailing;
  final VoidCallback? onTap;
  // Defaults match the app-wide type scale; Overview/Health Timeline/Symptoms/Upload pass a
  // slightly smaller size explicitly (see each tab) without shifting careloopTypeBody/Caption for
  // every other screen that uses this same row.
  final double labelSize;
  final double sublabelSize;
  const LedgerRow({
    super.key,
    this.leadingIcon,
    required this.label,
    this.sublabel,
    required this.trailing,
    this.onTap,
    this.labelSize = careloopTypeBody,
    this.sublabelSize = careloopTypeCaption,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        if (leadingIcon != null) ...[
          Icon(leadingIcon, size: 16, color: careloopMuted),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 600, not 500 — this label is almost always a test/medication/person name (a value
            // in its own right), not a field label.
            Text(label, style: TextStyle(fontSize: labelSize, fontWeight: FontWeight.w600, color: careloopTextPrimary), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (sublabel != null) ...[
              const SizedBox(height: 3),
              Text(sublabel!, style: TextStyle(fontSize: sublabelSize, fontWeight: FontWeight.w400, color: careloopMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ]),
        ),
        const SizedBox(width: 14),
        trailing,
      ]),
    );
    return onTap != null ? InkWell(onTap: onTap, child: content) : content;
  }
}

/// The value column (Section 2.2/3.3) — the number in tabular IBM Plex Mono, the unit trailing in
/// smaller muted text. This is the detail that makes the ledger metaphor read as precise data
/// rather than a decorative style choice; don't substitute a plain Text widget here.
class LedgerValue extends StatelessWidget {
  final String value;
  final String? unit;
  final TextAlign align;
  const LedgerValue(this.value, {super.key, this.unit, this.align = TextAlign.right});

  @override
  Widget build(BuildContext context) {
    return RichText(
      textAlign: align,
      text: TextSpan(children: [
        TextSpan(text: value, style: careloopDataInline()),
        if (unit != null) TextSpan(text: ' $unit', style: careloopDataInline(size: careloopTypeCaption, color: careloopMuted, weight: FontWeight.w400)),
      ]),
    );
  }
}

/// A right-aligned value-over-flag trailing block — the common shape for a lab-result ledger row.
class LedgerValueFlag extends StatelessWidget {
  final String value;
  final String? unit;
  final String? flagLabel;
  final bool? outOfRange;
  const LedgerValueFlag({super.key, required this.value, this.unit, this.flagLabel, this.outOfRange});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      LedgerValue(value, unit: unit),
      if (flagLabel != null && outOfRange != null) ...[
        const SizedBox(height: 3),
        LedgerFlag(flagLabel!, outOfRange: outOfRange!),
      ],
    ]);
  }
}

/// Wraps a list of [LedgerRow]s with hairline dividers between them (never after the last row —
/// see the appointments-list divider fix earlier in this app's history for why that matters), a
/// hairline border around the whole table, and a settle-in entrance for each row.
class LedgerTable extends StatelessWidget {
  final List<Widget> rows;
  final String? title;
  final IconData? titleIcon;
  const LedgerTable({super.key, required this.rows, this.title, this.titleIcon});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (title != null) SectionCaption(title!, icon: titleIcon),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: careloopSurface, border: careloopCardBorder, borderRadius: BorderRadius.circular(careloopRadiusMd), boxShadow: careloopCardShadow),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              FadeInUp(index: i, child: rows[i]),
              if (i < rows.length - 1) const Divider(height: 1),
            ],
          ],
        ),
      ),
    ]);
  }
}
