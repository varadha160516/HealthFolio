import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';
import 'prescription_view_screen.dart';

class VisitSummaryScreen extends StatefulWidget {
  final String appointmentId;
  const VisitSummaryScreen({super.key, required this.appointmentId});
  @override
  State<VisitSummaryScreen> createState() => _VisitSummaryScreenState();
}

class _VisitSummaryScreenState extends State<VisitSummaryScreen> {
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _appt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final appt = await api.getAppointment(widget.appointmentId);
    final summary = await api.getVisitSummary(widget.appointmentId);
    if (mounted) {
      setState(() {
        _appt = appt;
        _summary = summary;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_summary == null) return const DocGradientScaffold(body: LoadingCenter());
    final member = _appt?['member'] as Map<String, dynamic>?;
    final notes = _summary!['consultationNotes'] as Map<String, dynamic>?;
    final prescription = _summary!['prescription'] as Map<String, dynamic>?;
    final lineItems = ((prescription?['lineItems'] as List?) ?? []).cast<Map<String, dynamic>>();
    final vitals = (_summary!['vitals'] as List).cast<Map<String, dynamic>>();
    final labOrders = (_summary!['labOrders'] as List).cast<Map<String, dynamic>>();
    final v = vitals.isNotEmpty ? vitals.first : null;
    final symptoms = (notes?['symptoms'] as List?)?.cast<String>() ?? [];
    final advice = (notes?['advice'] as List?)?.cast<String>() ?? [];
    final examination = notes?['examination'] as Map<String, dynamic>?;
    final general = examination?['general'] as Map<String, dynamic>?;
    final system = examination?['system'] as Map<String, dynamic>?;
    final examLines = _examinationLines(general, system);
    final indications = labOrders.map((o) => o['clinical_indication']).where((i) => i != null && (i as String).isNotEmpty).toSet();

    return DocGradientScaffold(
      appBar: AppBar(title: const Text('Visit summary')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: docSuccessBg, borderRadius: BorderRadius.circular(docRadiusMd)),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(gradient: LinearGradient(colors: docPrimaryGradient), shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Visit completed', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                  Text('${member?['name'] ?? ''} · access to their records has been revoked', style: const TextStyle(fontSize: 11.5, color: docMuted)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          DocCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (notes?['chief_complaint'] != null && (notes!['chief_complaint'] as String).isNotEmpty)
                _row('Chief complaint', '${notes['chief_complaint']}${(notes['symptom_duration'] as String? ?? '').isNotEmpty ? ' · ${notes['symptom_duration']} duration' : ''}'),
              if (symptoms.isNotEmpty) _row('Symptoms', symptoms.join(' · ')),
              if (v != null) _row('Vitals', _vitalsLine(v)),
              if (examLines.isNotEmpty) _row('Examination', examLines.join('\n')),
              if (prescription?['diagnosis_text'] != null)
                _row('Diagnosis', '${prescription!['diagnosis_text']}${prescription['icd_code'] != null ? ' · ICD-10: ${prescription['icd_code']}' : ''}'),
              if (lineItems.isNotEmpty) _medicationsRow(lineItems),
              if (labOrders.isNotEmpty)
                _row('Lab tests', '${labOrders.expand((o) => (o['test_names'] as List)).join(' · ')}${indications.isNotEmpty ? '\nIndication: ${indications.join(', ')}' : ''}'),
              if (notes?['assessment_notes'] != null && (notes!['assessment_notes'] as String).isNotEmpty) _row('Assessment & plan', notes['assessment_notes']),
              if (advice.isNotEmpty) _row('Advice', advice.join(' · ')),
              if (notes?['follow_up_after'] != null) _followUpRow(notes!['follow_up_after'] as String, notes['follow_up_reason'] as String?),
            ]),
          ),
          const SizedBox(height: 20),
          if (prescription != null) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.description_outlined, size: 17),
                label: const Text('View prescription'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PrescriptionViewScreen(appointmentId: widget.appointmentId))),
              ),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: const Text('Back to appointments'),
            ),
          ),
        ],
      ),
    );
  }

  String _vitalsLine(Map<String, dynamic> v) {
    final parts = <String>[];
    if (v['systolic_bp'] != null || v['diastolic_bp'] != null) parts.add('BP ${v['systolic_bp'] ?? '—'}/${v['diastolic_bp'] ?? '—'}');
    if (v['heart_rate'] != null) parts.add('Pulse ${v['heart_rate']} bpm');
    if (v['spo2'] != null) parts.add('SpO₂ ${v['spo2']}%');
    if (v['temperature_f'] != null) parts.add('Temp ${v['temperature_f']}°F');
    if (v['respiratory_rate'] != null) parts.add('RR ${v['respiratory_rate']}/min');
    if (v['weight_kg'] != null) parts.add('Weight ${v['weight_kg']} kg');
    if (v['height_cm'] != null) parts.add('Height ${v['height_cm']} cm');
    return parts.isEmpty ? 'No vitals recorded' : parts.join(' · ');
  }

  List<String> _examinationLines(Map<String, dynamic>? general, Map<String, dynamic>? system) {
    final lines = <String>[];
    if (general != null) {
      final g = [general['condition'], general['consciousness'], general['hydration']].where((x) => x != null && (x as String).isNotEmpty).join(', ');
      if (g.isNotEmpty) lines.add('General: $g');
    }
    if (system != null) {
      final resp = ((system['respiratory'] as List?) ?? []).cast<String>();
      if (resp.isNotEmpty) lines.add('Respiratory: ${resp.join(', ')}');
      for (final key in const [('cardiovascular', 'Cardiovascular'), ('abdomen', 'Abdomen'), ('cns', 'CNS')]) {
        final v = system[key.$1] as String?;
        if (v != null && v.isNotEmpty) lines.add('${key.$2}: $v');
      }
    }
    return lines;
  }

  Widget _medicationsRow(List<Map<String, dynamic>> lineItems) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('MEDICATIONS', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
          const SizedBox(height: 6),
          for (final li in lineItems)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(color: docAccentLight, borderRadius: BorderRadius.circular(docRadiusSm)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text('${li['medicine_name']}${(li['strength'] as String? ?? '').isNotEmpty ? ' ${li['strength']}' : ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                  _timeDots(li['frequency'] as String?),
                ]),
                Text(
                  [li['dosage'], li['frequency'], li['duration'], li['instructions']].where((x) => x != null && (x as String).isNotEmpty).join(' · '),
                  style: const TextStyle(fontSize: 11.5, color: docMuted),
                ),
              ]),
            ),
        ]),
      );

  static const _timesOfDay = ['Morning', 'Afternoon', 'Evening', 'Night', 'Bedtime'];

  Widget _timeDots(String? frequency) {
    final f = frequency ?? '';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final t in _timesOfDay)
        Padding(
          padding: const EdgeInsets.only(left: 3),
          child: Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: f.contains(t) ? docPrimary : docBorder)),
        ),
    ]);
  }

  String _followUpLabel(String v) => switch (v) {
        '3_days' => '3 days',
        '1_week' => '1 week',
        '1_month' => '1 month',
        _ => 'As needed',
      };

  Widget _followUpRow(String after, String? reason) {
    final start = DateTime.now();
    DateTime? end;
    if (after == '3_days') end = start.add(const Duration(days: 3));
    if (after == '1_week') end = start.add(const Duration(days: 7));
    if (after == '1_month') end = DateTime(start.year, start.month + 1, start.day);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('FOLLOW-UP', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        const SizedBox(height: 3),
        Text('${_followUpLabel(after)}${(reason ?? '').isNotEmpty ? ' · $reason' : ''}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.4)),
        if (end != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Text(DateFormat('d MMM').format(start), style: const TextStyle(fontSize: 10, color: docMuted)),
            const SizedBox(width: 8),
            Expanded(
              child: Stack(clipBehavior: Clip.none, children: [
                Container(height: 4, decoration: BoxDecoration(color: docBorder, borderRadius: BorderRadius.circular(3))),
                Positioned(left: 0, top: -3, child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: docPrimary, shape: BoxShape.circle))),
              ]),
            ),
            const SizedBox(width: 8),
            Text(DateFormat('d MMM').format(end), style: const TextStyle(fontSize: 10, color: docMuted)),
          ]),
        ],
      ]),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k.toUpperCase(), style: const TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
          const SizedBox(height: 3),
          Text(v, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.4)),
        ]),
      );
}
