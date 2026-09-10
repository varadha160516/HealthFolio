import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';

/// Computed on read from existing appointment/prescription/consultation-notes data — no charting
/// package added; a plain bar-style visualization built from Containers is enough for weekly
/// volume, and everything else is just numbers/lists.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Map<String, dynamic>? _analytics;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await context.read<AuthProvider>().api.getAnalytics();
    if (mounted) setState(() => _analytics = data);
  }

  @override
  Widget build(BuildContext context) {
    if (_analytics == null) return const DocGradientScaffold(body: LoadingCenter());
    final weeklyVolume = (_analytics!['weeklyVolume'] as List).cast<Map<String, dynamic>>();
    final totals = _analytics!['totals'] as Map<String, dynamic>;
    final topDiagnoses = (_analytics!['topDiagnoses'] as List).cast<Map<String, dynamic>>();
    final followUps = _analytics!['followUps'] as Map<String, dynamic>;

    final total = totals['total'] as int;
    final cancelled = totals['cancelled'] as int;
    final noShow = totals['noShow'] as int;
    final cancelRate = total == 0 ? 0.0 : (cancelled + noShow) / total * 100;
    final advised = followUps['advised'] as int;
    final scheduled = followUps['scheduled'] as int;
    final complianceRate = advised == 0 ? 0.0 : scheduled / advised * 100;
    final maxCount = weeklyVolume.isEmpty ? 1 : weeklyVolume.map((w) => w['count'] as int).reduce((a, b) => a > b ? a : b);

    return DocGradientScaffold(
      appBar: AppBar(title: const Text('Reports & Analytics')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const Text('PATIENT VOLUME (LAST 8 WEEKS)', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            const SizedBox(height: 8),
            DocCard(
              child: weeklyVolume.isEmpty
                  ? const Text('No appointments in this window yet.', style: TextStyle(fontSize: 12.5, color: docMuted))
                  : SizedBox(
                      height: 90,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final w in weeklyVolume)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                                  Text('${w['count']}', style: const TextStyle(fontSize: 9.5, color: docMuted, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 3),
                                  Container(
                                    height: 56 * ((w['count'] as int) / maxCount).clamp(0.05, 1.0),
                                    decoration: BoxDecoration(gradient: const LinearGradient(colors: docPrimaryGradient, begin: Alignment.bottomCenter, end: Alignment.topCenter), borderRadius: BorderRadius.circular(4)),
                                  ),
                                ]),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: _StatCard(label: 'Total visits', value: '$total')),
              const SizedBox(width: 10),
              Expanded(child: _StatCard(label: 'Cancel / no-show', value: '${cancelRate.toStringAsFixed(0)}%')),
              const SizedBox(width: 10),
              Expanded(child: _StatCard(label: 'Follow-up compliance', value: '${complianceRate.toStringAsFixed(0)}%')),
            ]),
            const SizedBox(height: 20),
            const Text('TOP DIAGNOSES', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            const SizedBox(height: 8),
            if (topDiagnoses.isEmpty)
              DocCard(child: const Text('No diagnoses recorded yet.', style: TextStyle(fontSize: 12.5, color: docMuted)))
            else
              DocCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(children: [
                  for (final d in topDiagnoses)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                      child: Row(children: [
                        Expanded(child: Text(d['diagnosis_text'] as String? ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                        Text('${d['count']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: docAccent)),
                      ]),
                    ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return DocCard(
      padding: const EdgeInsets.all(13),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}
