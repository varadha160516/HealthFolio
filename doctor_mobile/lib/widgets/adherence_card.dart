import 'package:flutter/material.dart';
import '../theme.dart';

/// What the patient logged in HealthFolio against their medicines over the last 7 completed days
/// (server/src/pipeline/adherence.ts). Deliberately honest about what it can't know: a dose that
/// was never logged is "not logged", never "missed" — a patient who ignores the reminders looks
/// exactly like one who skipped everything, and the card says so rather than implying blame.
class AdherenceCard extends StatelessWidget {
  final Map<String, dynamic> report;
  const AdherenceCard({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final meds = ((report['medications'] as List?) ?? const []).cast<Map<String, dynamic>>();
    if (meds.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: docSurface, borderRadius: BorderRadius.circular(docRadiusMd), border: docCardBorder),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.medication_liquid_rounded, size: 15, color: docAccentDark),
          SizedBox(width: 6),
          Text('MEDICATION ADHERENCE · LAST 7 DAYS', style: TextStyle(fontSize: 10, color: docAccentDark, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        ]),
        const SizedBox(height: 10),
        for (var i = 0; i < meds.length; i++) ...[
          if (i > 0) const Divider(height: 18),
          _MedicationRow(med: meds[i]),
        ],
        const SizedBox(height: 10),
        const Text(
          'From the patient\'s own logging in HealthFolio. "Not logged" means no entry was made — not that a dose was missed.',
          style: TextStyle(fontSize: 10.5, color: docMuted, fontStyle: FontStyle.italic, height: 1.4),
        ),
      ]),
    );
  }
}

class _MedicationRow extends StatelessWidget {
  final Map<String, dynamic> med;
  const _MedicationRow({required this.med});

  @override
  Widget build(BuildContext context) {
    final name = [med['medicine_name'], med['strength']].where((v) => v != null && (v as String).isNotEmpty).join(' ');
    final byYou = med['prescribed_by_you'] == true;
    final expected = (med['expected'] as num?)?.toInt() ?? 0;
    final taken = (med['taken'] as num?)?.toInt() ?? 0;
    final skipped = (med['skipped'] as num?)?.toInt() ?? 0;
    final notLogged = (med['not_logged'] as num?)?.toInt() ?? 0;
    final pct = (med['taken_pct'] as num?)?.toInt();
    final uses = (med['as_needed_uses'] as num?)?.toInt();

    final Widget detail;
    if (uses != null) {
      detail = Text('As needed — used $uses time${uses == 1 ? '' : 's'} this week', style: const TextStyle(fontSize: 12, color: docMuted));
    } else if (expected == 0) {
      detail = const Text('Started too recently to show a pattern yet.', style: TextStyle(fontSize: 12, color: docMuted));
    } else if (taken == 0 && skipped == 0) {
      detail = const Text('No doses logged this week — the patient may not be using the reminders.', style: TextStyle(fontSize: 12, color: docMuted, height: 1.35));
    } else {
      final color = pct! >= 80 ? docSuccess : (pct >= 50 ? docWarning : docDanger);
      detail = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(value: taken / expected, minHeight: 6, backgroundColor: docBorder, color: color),
        ),
        const SizedBox(height: 5),
        Text(
          '$taken of $expected logged as taken${skipped > 0 ? ' · $skipped skipped' : ''}${notLogged > 0 ? ' · $notLogged not logged' : ''}',
          style: const TextStyle(fontSize: 12, color: docMuted),
        ),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
        if (byYou)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: docAccentLight, borderRadius: BorderRadius.circular(999)),
            child: const Text('You prescribed', style: TextStyle(fontSize: 9.5, color: docAccentDark, fontWeight: FontWeight.w700)),
          ),
      ]),
      const SizedBox(height: 6),
      detail,
    ]);
  }
}
