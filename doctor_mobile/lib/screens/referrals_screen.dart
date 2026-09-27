import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';
import '../widgets/follow_up_timeline.dart';

/// Closed-loop referrals: every referral this doctor has sent, and — once the specialist completes
/// that visit — what came back. The outcome is copied programmatically from the specialist's own
/// visit (diagnosis, medicines, advice, follow-up), never drafted or summarized, the same "organize
/// what was said" rule as everywhere else in this app that touches another provider's record.
class ReferralsScreen extends StatefulWidget {
  const ReferralsScreen({super.key});
  @override
  State<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends State<ReferralsScreen> {
  Map<String, dynamic>? _summary;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await context.read<AuthProvider>().api.getMyReferrals();
      if (mounted) setState(() => _summary = s);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  (String, Color, Color) _statusStyle(String status) => switch (status) {
        'completed' => ('Outcome ready', docSuccess, docSuccessBg),
        'booked' => ('Booked', docAccent, docAccentLight),
        'cancelled' => ('Cancelled', docMuted, docSurfaceRaised),
        _ => ('Waiting on patient', docWarning, docWarningBg),
      };

  @override
  Widget build(BuildContext context) {
    final referrals = ((_summary?['referrals'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return DocGradientScaffold(
      appBar: AppBar(title: const Text('Referrals')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _summary == null && _error == null
            ? const LoadingCenter()
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: docDangerBg, borderRadius: BorderRadius.circular(docRadiusMd)),
                      child: Text(_error!, style: const TextStyle(color: docDanger, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                  if (_summary != null) ...[
                    DocCard(
                      child: Row(children: [
                        _stat('Sent', _summary!['sent'] as int, docTextPrimary),
                        _stat('Outcomes back', _summary!['outcomes_ready'] as int, docSuccess),
                        _stat('Still open', (_summary!['sent'] as int) - (_summary!['outcomes_ready'] as int), docWarning),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    if (referrals.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 40),
                        child: EmptyState(icon: Icons.call_split_rounded, message: 'No referrals sent yet.\nRefer a patient from an unlocked visit to start closing the loop.'),
                      )
                    else
                      for (final r in referrals) _referralCard(r),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _stat(String label, int n, Color color) => Expanded(
        child: Column(children: [
          Text('$n', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(fontSize: 10.5, color: docMuted, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _referralCard(Map<String, dynamic> r) {
    final outcome = r['outcome'] as Map<String, dynamic>?;
    final (statusLabel, fg, bg) = _statusStyle(r['status'] as String);
    final dt = DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal();
    final target = (r['target_provider_name'] as String?) ?? (r['target_specialty'] as String?) ?? 'a specialist';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DocCard(
        padding: const EdgeInsets.all(13),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r['patient_name'] as String? ?? 'Patient', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                const SizedBox(height: 2),
                Text('Referred to $target${dt != null ? ' · ${DateFormat('MMM d').format(dt)}' : ''}', style: const TextStyle(fontSize: 12, color: docMuted)),
              ]),
            ),
            if (r['urgency'] == 'urgent')
              Padding(padding: const EdgeInsets.only(right: 6, top: 1), child: _chip('Urgent', docDanger, docDangerBg)),
            _chip(statusLabel, fg, bg),
          ]),
          if (outcome != null) ...[
            const Divider(height: 20),
            _outcome(outcome),
          ],
        ]),
      ),
    );
  }

  Widget _outcome(Map<String, dynamic> outcome) {
    final medicines = (outcome['medicines'] as List?)?.cast<String>() ?? const [];
    final advice = (outcome['advice'] as List?)?.cast<String>() ?? const [];
    final flags = (outcome['safety_flags'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final diagnosis = outcome['diagnosis_text'] as String?;
    final followUpAfter = outcome['follow_up_after'] as String?;
    final hasAnything = diagnosis != null || medicines.isNotEmpty || advice.isNotEmpty || followUpAfter != null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (flags.isNotEmpty) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(11),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: docWarningBg, borderRadius: BorderRadius.circular(docRadiusMd)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.shield_outlined, size: 14, color: docWarning),
              const SizedBox(width: 6),
              Text('SAFETY FLAG FROM THIS VISIT · ${flags.length}', style: const TextStyle(fontSize: 9.5, color: docWarning, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            ]),
            const SizedBox(height: 6),
            for (final f in flags) ...[
              Text(f['title'] as String? ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: docWarning)),
              Text(f['detail'] as String? ?? '', style: const TextStyle(fontSize: 11.5, height: 1.35, color: docWarning)),
              if (f != flags.last) const SizedBox(height: 6),
            ],
          ]),
        ),
      ],
      if (!hasAnything)
        const Text('The specialist completed the visit but recorded no diagnosis, prescription or follow-up.', style: TextStyle(fontSize: 12, color: docMuted, fontStyle: FontStyle.italic))
      else ...[
        if (diagnosis != null) _kv('Diagnosis', diagnosis),
        if (medicines.isNotEmpty) _kv('Prescribed', medicines.join(', ')),
        if (advice.isNotEmpty) _kv('Advice', advice.join(' · ')),
        if (followUpAfter != null) _kv('Follow-up', followUpLabel(followUpAfter) + (outcome['follow_up_reason'] != null ? ' — ${outcome['follow_up_reason']}' : '')),
      ],
    ]);
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: RichText(text: TextSpan(children: [
          TextSpan(text: '$k: ', style: const TextStyle(color: docMuted, fontSize: 12.5, fontWeight: FontWeight.w600)),
          TextSpan(text: v, style: const TextStyle(color: docTextPrimary, fontSize: 12.5)),
        ])),
      );

  Widget _chip(String label, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
      );
}
