import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme.dart';

String followUpLabel(String v) => switch (v) {
      '3_days' => '3 days',
      '1_week' => '1 week',
      '1_month' => '1 month',
      _ => 'As needed',
    };

DateTime? followUpEndDate(String after, DateTime start) => switch (after) {
      '3_days' => start.add(const Duration(days: 3)),
      '1_week' => start.add(const Duration(days: 7)),
      '1_month' => DateTime(start.year, start.month + 1, start.day),
      _ => null,
    };

/// The redesigned follow-up display — a labeled card with the reason, a start→end date
/// gradient timeline (not just a bare progress line), and a "due in N days" badge. Used
/// identically by Visit Summary and Prescription so a follow-up reads the same wherever it
/// shows up, per the request to redesign this UI consistently across both screens.
class FollowUpTimeline extends StatelessWidget {
  final String after;
  final String? reason;
  const FollowUpTimeline({super.key, required this.after, this.reason});

  @override
  Widget build(BuildContext context) {
    final start = DateTime.now();
    final end = followUpEndDate(after, start);
    final daysLeft = end?.difference(start).inDays;

    return DocCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              '${followUpLabel(after)}${(reason ?? '').isNotEmpty ? ' — $reason' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
            ),
          ),
        ]),
        if (end != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            Text(DateFormat('MMM d').format(start), style: const TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 12,
                child: Stack(clipBehavior: Clip.none, alignment: Alignment.centerLeft, children: [
                  Container(height: 6, decoration: BoxDecoration(color: docSurfaceRaised, borderRadius: BorderRadius.circular(4))),
                  FractionallySizedBox(
                    widthFactor: 0.32,
                    alignment: Alignment.centerLeft,
                    child: Stack(clipBehavior: Clip.none, alignment: Alignment.centerRight, children: [
                      Container(height: 6, decoration: BoxDecoration(gradient: const LinearGradient(colors: docPrimaryGradient), borderRadius: BorderRadius.circular(4))),
                      Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: docPrimary, width: 3))),
                    ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            Text(DateFormat('MMM d').format(end), style: const TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700)),
          ]),
          if (daysLeft != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: docWarningBg, borderRadius: BorderRadius.circular(docRadiusPill)),
              child: Text(
                daysLeft <= 0 ? 'Due today' : 'Due in $daysLeft day${daysLeft == 1 ? '' : 's'}',
                style: const TextStyle(color: docWarning, fontWeight: FontWeight.w700, fontSize: 10.5),
              ),
            ),
          ],
        ],
      ]),
    );
  }
}
