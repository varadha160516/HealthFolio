import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';
import '../widgets/follow_up_timeline.dart';
import '../widgets/signature_pad.dart';

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

    final issuedAt = prescription['issued_at'] != null ? DateTime.tryParse(prescription['issued_at'])?.toLocal() : null;

    return DocGradientScaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Prescription', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Text(member?['name'] ?? '', style: const TextStyle(fontSize: 11, color: docMuted)),
        ]),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          // One continuous letterhead document instead of many small disconnected cards — the
          // Rx (medications) section is the visual hero, everything else reads as supporting detail.
          ClipRRect(
            borderRadius: BorderRadius.circular(docRadiusMd),
            child: Container(
              decoration: BoxDecoration(color: Colors.white, boxShadow: docRaisedShadow),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(height: 5, decoration: const BoxDecoration(gradient: LinearGradient(colors: docPrimaryGradient))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(gradient: const LinearGradient(colors: docPrimaryGradient), borderRadius: BorderRadius.circular(13)),
                      child: Center(child: Text(_initials(provider?['name'] as String? ?? '?'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(provider?['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        Text(
                          [provider?['specialty'], provider?['clinic_name']].where((v) => v != null && (v as String).isNotEmpty).join(' · '),
                          style: const TextStyle(fontSize: 10.5, color: docMuted),
                        ),
                        if ((provider?['registration_number'] as String? ?? '').isNotEmpty)
                          Text('Reg. No. ${provider!['registration_number']}', style: const TextStyle(fontSize: 9, color: docMutedDim, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    if (issuedAt != null)
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        const Text('PRESCRIPTION', style: TextStyle(fontSize: 8.5, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                        const SizedBox(height: 2),
                        Text('${issuedAt.day}/${issuedAt.month}/${issuedAt.year}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: docAccentDark)),
                      ]),
                  ]),
                ),
                const Divider(height: 1, color: docBorder),
                Container(
                  color: docSurfaceRaised,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: Center(child: Text(_initials(member?['name'] as String? ?? '?'), style: const TextStyle(color: docAccentDark, fontWeight: FontWeight.w700, fontSize: 12))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(member?['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        Text('${age != null ? '$age yrs' : ''}${sex != null && sex.isNotEmpty ? ' · ${sex[0].toUpperCase()}${sex.substring(1)}' : ''}', style: const TextStyle(fontSize: 10.5, color: docMuted)),
                      ]),
                    ),
                  ]),
                ),
                if ((notes?['chief_complaint'] as String? ?? '').isNotEmpty || symptoms.isNotEmpty || v != null || prescription['diagnosis_text'] != null)
                  _infoGrid([
                    if ((notes?['chief_complaint'] as String? ?? '').isNotEmpty || symptoms.isNotEmpty)
                      _infoCell(
                          'Chief complaint',
                          '${notes?['chief_complaint'] ?? symptoms.join(', ')}${(notes?['symptom_duration'] as String? ?? '').isNotEmpty ? ' · ${notes!['symptom_duration']}' : ''}'),
                    if (v != null) _infoCell('Vitals', _vitalsLine(v)),
                    if (prescription['diagnosis_text'] != null)
                      _infoCell('Diagnosis', '${prescription['diagnosis_text']}${prescription['icd_code'] != null ? '  ·  ICD-10 ${prescription['icd_code']}' : ''}', full: true),
                  ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                  child: Row(children: [
                    Text('℞', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: docAccentDark, fontStyle: FontStyle.italic)),
                    const SizedBox(width: 8),
                    const Text('Medications', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text('${lineItems.length} item${lineItems.length == 1 ? '' : 's'}', style: const TextStyle(fontSize: 10, color: docMuted, fontWeight: FontWeight.w600)),
                  ]),
                ),
                for (int i = 0; i < lineItems.length; i++)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 20,
                        height: 20,
                        margin: const EdgeInsets.only(top: 1),
                        decoration: BoxDecoration(color: docAccentLight, shape: BoxShape.circle),
                        child: Center(child: Text('${i + 1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: docAccentDark))),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text.rich(TextSpan(children: [
                            TextSpan(text: lineItems[i]['medicine_name'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: docTextPrimary)),
                            if ((lineItems[i]['strength'] as String? ?? '').isNotEmpty)
                              TextSpan(text: '  ${lineItems[i]['strength']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: docMuted)),
                          ])),
                          const SizedBox(height: 5),
                          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                            if ((lineItems[i]['duration'] as String? ?? '').isNotEmpty) _medTag(lineItems[i]['duration']),
                            if ((lineItems[i]['instructions'] as String? ?? '').isNotEmpty) _medTag(lineItems[i]['instructions']),
                            _timeDots(lineItems[i]['frequency'] as String?),
                          ]),
                        ]),
                      ),
                    ]),
                  ),
                if (labOrders.isNotEmpty) _docSection('Investigations ordered', Text(labOrders.expand((o) => (o['test_names'] as List)).join(' · '), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                if (advice.isNotEmpty)
                  _docSection(
                    'Advice',
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final a in advice) Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('•  $a', style: const TextStyle(fontSize: 12.5, height: 1.5)))]),
                  ),
                if ((notes?['assessment_notes'] as String? ?? '').isNotEmpty)
                  _docSection('Assessment & next steps', Text(notes!['assessment_notes'], style: const TextStyle(fontSize: 12.5, height: 1.5))),
                if (notes?['follow_up_after'] != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('FOLLOW-UP', style: TextStyle(fontSize: 9, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4))),
                      FollowUpTimeline(after: notes!['follow_up_after'] as String, reason: notes['follow_up_reason'] as String?),
                    ]),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                      child: Text(
                        'This is a digitally generated prescription issued via ClinDesk. Valid without a physical signature.',
                        style: const TextStyle(fontSize: 8.5, color: docMutedDim, height: 1.4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      if ((provider?['signature_base64'] as String? ?? '').isNotEmpty)
                        SignaturePreview(base64Png: provider!['signature_base64'] as String)
                      else
                        Text(provider?['name'] ?? '', style: const TextStyle(fontFamily: 'Georgia', fontStyle: FontStyle.italic, fontSize: 18, color: docAccentDark)),
                      Container(margin: const EdgeInsets.only(top: 2), width: 90, height: 1, color: docTextPrimary),
                      const SizedBox(height: 4),
                      Text(provider?['name'] ?? '', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700)),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoGrid(List<Widget> cells) {
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 2) {
      rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: cells[i]), if (i + 1 < cells.length) Expanded(child: cells[i + 1])]));
    }
    return Column(children: rows);
  }

  Widget _infoCell(String label, String value, {bool full = false}) => Container(
        width: full ? double.infinity : null,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: docBorder))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 8.5, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.35)),
        ]),
      );

  Widget _medTag(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: docSurfaceRaised, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: docTextPrimary)),
      );

  Widget _docSection(String label, Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: docBorder))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
          const SizedBox(height: 8),
          child,
        ]),
      );

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

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}
