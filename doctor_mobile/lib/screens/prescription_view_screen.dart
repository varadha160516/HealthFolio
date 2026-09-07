import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';

/// A standalone, shareable-feeling view of a signed prescription — reached from Visit Summary.
/// Deliberately does NOT re-fetch the patient's allergy/health record: once a visit is completed,
/// grantsDataAccess() is false and that data is gone from the API response (Section 7.2's "not
/// standing access"), so this screen only ever shows what was actually authored into the
/// prescription/consultation record itself, via the same visit-summary endpoint VisitSummaryScreen
/// uses (that one route deliberately stays readable regardless of status — see doctorApp.ts).
class PrescriptionViewScreen extends StatefulWidget {
  final String appointmentId;
  const PrescriptionViewScreen({super.key, required this.appointmentId});
  @override
  State<PrescriptionViewScreen> createState() => _PrescriptionViewScreenState();
}

class _PrescriptionViewScreenState extends State<PrescriptionViewScreen> {
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

  static const _timesOfDay = ['Morning', 'Afternoon', 'Evening', 'Night'];

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

  @override
  Widget build(BuildContext context) {
    if (_summary == null) return const DocGradientScaffold(body: LoadingCenter());
    final member = _appt?['member'] as Map<String, dynamic>?;
    final provider = _appt?['provider'] as Map<String, dynamic>?;
    final notes = _summary!['consultationNotes'] as Map<String, dynamic>?;
    final prescription = _summary!['prescription'] as Map<String, dynamic>?;
    final lineItems = ((prescription?['lineItems'] as List?) ?? []).cast<Map<String, dynamic>>();
    final labOrders = (_summary!['labOrders'] as List).cast<Map<String, dynamic>>();
    final advice = (notes?['advice'] as List?)?.cast<String>() ?? [];
    final symptoms = (notes?['symptoms'] as List?)?.cast<String>() ?? [];
    final vitals = (_summary!['vitals'] as List).cast<Map<String, dynamic>>();
    final v = vitals.isNotEmpty ? vitals.first : null;
    final dob = member?['dob'] as String?;
    final age = dob != null ? (DateTime.now().difference(DateTime.tryParse(dob) ?? DateTime.now()).inDays / 365.25).floor() : null;
    final sex = member?['sex'] as String?;

    if (prescription == null) {
      return DocGradientScaffold(
        appBar: AppBar(title: const Text('Prescription')),
        body: const Center(child: EmptyState(icon: Icons.medication_outlined, message: 'No prescription was issued for this visit.')),
      );
    }

    return DocGradientScaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Prescription', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Text(member?['name'] ?? '', style: const TextStyle(fontSize: 11, color: docMuted)),
        ]),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (provider != null)
            DocCard(
              padding: const EdgeInsets.all(13),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: docAccentLight, borderRadius: BorderRadius.circular(9)),
                  child: const Icon(Icons.local_hospital_rounded, size: 16, color: docPrimary),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(provider['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    if (provider['specialty'] != null) Text(provider['specialty'], style: const TextStyle(fontSize: 10.5, color: docMuted)),
                  ]),
                ),
              ]),
            ),
          const SizedBox(height: 12),
          Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(gradient: LinearGradient(colors: docPrimaryGradient), shape: BoxShape.circle),
              child: Center(child: Text(_initials(member?['name'] ?? '?'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
            ),
            const SizedBox(width: 11),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${member?['name'] ?? ''}${age != null ? ' · $age${sex != null && sex.isNotEmpty ? sex[0].toUpperCase() : ''}' : ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              if (prescription['issued_at'] != null) Text('Issued ${DateTime.tryParse(prescription['issued_at'])?.toLocal().toString().substring(0, 16) ?? ''}', style: const TextStyle(fontSize: 10.5, color: docMuted)),
            ]),
          ]),
          const SizedBox(height: 18),
          if ((notes?['chief_complaint'] as String? ?? '').isNotEmpty || symptoms.isNotEmpty) ...[
            const Text('CHIEF COMPLAINT', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            const SizedBox(height: 6),
            DocCard(
              padding: const EdgeInsets.all(13),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if ((notes?['chief_complaint'] as String? ?? '').isNotEmpty)
                  Text(
                    '${notes!['chief_complaint']}${(notes['symptom_duration'] as String? ?? '').isNotEmpty ? ' · ${notes['symptom_duration']} duration' : ''}',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                if (symptoms.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(symptoms.join(' · '), style: const TextStyle(fontSize: 12.5, color: docMuted)),
                ],
              ]),
            ),
            const SizedBox(height: 18),
          ],
          if (v != null) ...[
            const Text('VITALS', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            const SizedBox(height: 6),
            DocCard(padding: const EdgeInsets.all(13), child: Text(_vitalsLine(v), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            const SizedBox(height: 18),
          ],
          if (prescription['diagnosis_text'] != null) ...[
            const Text('DIAGNOSIS', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            const SizedBox(height: 6),
            DocCard(
              padding: const EdgeInsets.all(13),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(prescription['diagnosis_text'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                if (prescription['icd_code'] != null) Text('ICD-10: ${prescription['icd_code']}', style: const TextStyle(fontSize: 10.5, color: docMuted)),
              ]),
            ),
            const SizedBox(height: 18),
          ],
          const Text('MEDICATIONS', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
          const SizedBox(height: 6),
          DocCard(
            padding: const EdgeInsets.all(13),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (int i = 0; i < lineItems.length; i++)
                Container(
                  margin: EdgeInsets.only(top: i == 0 ? 0 : 8),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                  decoration: BoxDecoration(color: docAccentLight, borderRadius: BorderRadius.circular(docRadiusSm)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text('${lineItems[i]['medicine_name']}${(lineItems[i]['strength'] as String? ?? '').isNotEmpty ? ' ${lineItems[i]['strength']}' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                      _timeDots(lineItems[i]['frequency'] as String?),
                    ]),
                    Text(
                      [lineItems[i]['dosage'], lineItems[i]['frequency'], lineItems[i]['duration'], lineItems[i]['instructions']].where((x) => x != null && (x as String).isNotEmpty).join(' · '),
                      style: const TextStyle(fontSize: 11.5, color: docMuted),
                    ),
                  ]),
                ),
            ]),
          ),
          if (labOrders.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text('INVESTIGATIONS ORDERED', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            const SizedBox(height: 6),
            DocCard(padding: const EdgeInsets.all(13), child: Text(labOrders.expand((o) => (o['test_names'] as List)).join(' · '), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          ],
          if (advice.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text('ADVICE', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            const SizedBox(height: 6),
            DocCard(padding: const EdgeInsets.all(13), child: Text(advice.join(' · '), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          ],
          if ((notes?['assessment_notes'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text('ASSESSMENT & NEXT STEPS', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            const SizedBox(height: 6),
            DocCard(padding: const EdgeInsets.all(13), child: Text(notes!['assessment_notes'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          ],
          if (notes?['follow_up_after'] != null) ...[
            const SizedBox(height: 18),
            const Text('FOLLOW-UP', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            const SizedBox(height: 6),
            DocCard(padding: const EdgeInsets.all(13), child: _followUpContent(notes!['follow_up_after'] as String, notes['follow_up_reason'] as String?)),
          ],
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

  String _followUpLabel(String v) => switch (v) {
        '3_days' => '3 days',
        '1_week' => '1 week',
        '1_month' => '1 month',
        _ => 'As needed',
      };

  Widget _followUpContent(String after, String? reason) {
    final start = DateTime.now();
    DateTime? end;
    if (after == '3_days') end = start.add(const Duration(days: 3));
    if (after == '1_week') end = start.add(const Duration(days: 7));
    if (after == '1_month') end = DateTime(start.year, start.month + 1, start.day);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${_followUpLabel(after)}${(reason ?? '').isNotEmpty ? ' · $reason' : ''}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
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
    ]);
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}
