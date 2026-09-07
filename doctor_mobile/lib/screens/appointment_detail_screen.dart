import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../api_client.dart';
import '../auth_provider.dart';
import '../theme.dart';
import 'consultation_screen.dart';
import 'visit_summary_screen.dart';

const _waitingStates = {'checked_in', 'consent_requested'};

class AppointmentDetailScreen extends StatefulWidget {
  final String appointmentId;
  const AppointmentDetailScreen({super.key, required this.appointmentId});
  @override
  State<AppointmentDetailScreen> createState() => _AppointmentDetailScreenState();
}

class _AppointmentDetailScreenState extends State<AppointmentDetailScreen> {
  Map<String, dynamic>? _appt;
  List<dynamic>? _visitHistory;
  Timer? _poll;
  String? _error;
  String? _lastOtp;
  final _otpInput = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final appt = await api.getAppointment(widget.appointmentId);
    if (!mounted) return;
    setState(() => _appt = appt);
    _poll?.cancel();
    if (_waitingStates.contains(appt['status'])) {
      _poll = Timer(const Duration(seconds: 2), _load);
    }
    if (appt['status'] == 'consent_granted' && _visitHistory == null) {
      try {
        _visitHistory = await api.getPatientVisitHistory(widget.appointmentId);
        if (mounted) setState(() {});
      } catch (_) {}
    }
  }

  Future<dynamic> _act(Future<dynamic> Function() fn) async {
    setState(() => _error = null);
    try {
      final res = await fn();
      await _load();
      return res;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_appt == null) return const DocGradientScaffold(body: LoadingCenter());
    final appt = _appt!;
    final member = appt['member'] as Map<String, dynamic>?;
    final status = appt['status'] as String;
    final consentGrant = appt['consentGrant'] as Map<String, dynamic>?;
    final unlocked = status == 'consent_granted' || status == 'in_consultation';
    final dob = member?['dob'] as String?;
    final age = dob != null ? (DateTime.now().difference(DateTime.tryParse(dob) ?? DateTime.now()).inDays / 365.25).floor() : null;

    return DocGradientScaffold(
      appBar: AppBar(title: const Text('Patient snapshot')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(gradient: LinearGradient(colors: docPrimaryGradient), shape: BoxShape.circle),
              child: Center(child: Text(_initials(member?['name'] ?? '?'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(member?['name'] ?? 'Unknown patient', style: docPageTitle().copyWith(fontSize: 20)),
                const SizedBox(height: 2),
                Text('${age != null ? '$age years · ' : ''}${_cap(member?['sex'])}', style: const TextStyle(color: docMuted, fontSize: 12.5, fontWeight: FontWeight.w500)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (member?['blood_group'] != null) _chip('Blood group · ${member!['blood_group']}', docSurfaceRaised, docTextPrimary),
            StatusPill.forAppointment(status),
          ]),
          const SizedBox(height: 18),

          if (_error != null) _errorBanner(_error!),

          if (status == 'scheduled') _actionCard(
            title: 'Check in this patient',
            body: 'Grants no data access yet — only makes the consent-request action available.',
            button: 'Check in',
            onPressed: () => _act(() => context.read<AuthProvider>().api.checkIn(widget.appointmentId)),
          ),

          if (status == 'checked_in') DocCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Request consent for this visit', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: ElevatedButton(onPressed: () => _requestConsent('in_app'), child: const Text('Send in-app request'))),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => _requestConsent('otp'), child: const Text('Use OTP fallback'))),
              ]),
            ]),
          ),

          if (status == 'consent_requested') DocCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.hourglass_top_rounded, color: docInfo, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Waiting for the patient to respond (${consentGrant?['method'] == 'otp' ? 'OTP fallback' : 'in-app'})'
                    '${consentGrant?['expires_at'] != null ? ' — expires ${DateFormat('h:mm a').format(DateTime.parse(consentGrant!['expires_at']).toLocal())}' : ''}.',
                    style: const TextStyle(fontSize: 12.5, color: docMuted),
                  ),
                ),
              ]),
              if (consentGrant?['method'] == 'otp') ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(controller: _otpInput, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '6-digit code'))),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _act(() => context.read<AuthProvider>().api.verifyOtp(widget.appointmentId, _otpInput.text.trim())),
                    child: const Text('Verify'),
                  ),
                ]),
              ],
              if (_lastOtp != null) ...[
                const SizedBox(height: 8),
                Text('(demo only — code sent was $_lastOtp)', style: const TextStyle(color: docMutedDim, fontSize: 11.5, fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 10),
              OutlinedButton(onPressed: () => _resend(consentGrant?['method'] == 'otp' ? 'otp' : 'in_app'), child: const Text('Resend request')),
            ]),
          ),

          if (status == 'consent_denied' || status == 'consent_expired') _actionCard(
            title: status == 'consent_denied' ? 'Consent denied' : 'Consent request expired',
            body: status == 'consent_denied' ? 'The patient denied this consent request.' : 'The consent request expired without a response.',
            button: 'Resend request',
            onPressed: () => _resend('in_app'),
          ),

          if (unlocked && appt['unlockedData'] != null) ..._unlockedSections(appt['unlockedData']),

          if (status == 'consent_granted') ...[
            const SizedBox(height: 4),
            if (appt['reason_for_visit'] != null && (appt['reason_for_visit'] as String).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: DocCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text("TODAY'S REASON", style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                    const SizedBox(height: 6),
                    Text(appt['reason_for_visit'], style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start Consultation'),
                onPressed: () async {
                  await _act(() => context.read<AuthProvider>().api.startConsultation(widget.appointmentId));
                  if (mounted) {
                    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ConsultationScreen(appointmentId: widget.appointmentId)));
                  }
                },
              ),
            ),
          ],

          if (status == 'in_consultation') ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Resume consultation'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConsultationScreen(appointmentId: widget.appointmentId))),
              ),
            ),
          ],

          if (status == 'completed') ...[
            _actionCard(title: 'Visit completed', body: 'Access to this patient\'s records was revoked when the visit was completed.', button: null, onPressed: null),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VisitSummaryScreen(appointmentId: widget.appointmentId))),
                child: const Text('View visit summary'),
              ),
            ),
          ],

          if (status == 'cancelled') _actionCard(title: 'Appointment cancelled', body: 'The patient cancelled this appointment.', button: null, onPressed: null),
        ],
      ),
    );
  }

  List<Widget> _unlockedSections(Map<String, dynamic> data) {
    final summary = data['summary'] as Map<String, dynamic>;
    final allergies = (summary['allergies'] as List).map((a) => a['value']).join(', ');
    final chronic = (summary['chronicConditions'] as List).map((c) => c['value']).join(', ');
    final meds = (summary['currentMedications'] as List);
    final flagged = data['flaggedHistory'] as List;

    return [
      if (allergies.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(color: docDangerBg, borderRadius: BorderRadius.circular(docRadiusMd), border: Border.all(color: docDanger.withValues(alpha: 0.3))),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: docDanger, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text('Allergy: $allergies', style: const TextStyle(color: docDanger, fontWeight: FontWeight.w700, fontSize: 13.5))),
            ]),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: DocCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Allergies & conditions', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
            const SizedBox(height: 10),
            _kv('Allergies', allergies.isEmpty ? 'None recorded' : allergies),
            _kv('Chronic conditions', chronic.isEmpty ? 'None recorded' : chronic),
            _kv('Current medications', meds.isEmpty ? 'None' : meds.map((m) => m['medicine_name']).join(', ')),
          ]),
        ),
      ),
      if (flagged.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: DocCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Flagged history (out of range since last visit)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              const SizedBox(height: 10),
              for (final f in flagged) _kv(f['display_name'] ?? '', '${f['canonical_value'] ?? ''} ${f['canonical_unit'] ?? ''}'),
            ]),
          ),
        ),
      if (_visitHistory != null && _visitHistory!.isNotEmpty) _previousVisitCard(_visitHistory!.first as Map<String, dynamic>),
    ];
  }

  Widget _previousVisitCard(Map<String, dynamic> visit) {
    final notes = visit['consultationNotes'] as Map<String, dynamic>?;
    final prescription = visit['prescription'] as Map<String, dynamic>?;
    final labOrders = (visit['labOrders'] as List?) ?? [];
    final dt = DateTime.tryParse(visit['datetime'] as String? ?? '')?.toLocal();
    final symptoms = (notes?['symptoms'] as List?)?.cast<String>() ?? [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DocCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Previous visit summary', style: docSectionHeading().copyWith(fontSize: 14.5)),
          const SizedBox(height: 4),
          Text(dt != null ? DateFormat('MMM d, yyyy').format(dt) : '', style: const TextStyle(fontSize: 10.5, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
          const SizedBox(height: 10),
          if (prescription?['diagnosis_text'] != null) _kv('Diagnosis', prescription!['diagnosis_text']),
          if (symptoms.isNotEmpty) _kv('Symptoms', symptoms.join(' · ')),
          if (prescription != null && (prescription['lineItems'] as List).isNotEmpty)
            _kv('Medications', (prescription['lineItems'] as List).map((li) => li['medicine_name']).join(' · ')),
          if (labOrders.isNotEmpty) _kv('Tests', labOrders.expand((o) => (o['test_names'] as List)).join(' · ')),
        ]),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: RichText(text: TextSpan(children: [
          TextSpan(text: '$k: ', style: const TextStyle(color: docMuted, fontSize: 12.5, fontWeight: FontWeight.w600)),
          TextSpan(text: v, style: const TextStyle(color: docTextPrimary, fontSize: 12.5)),
        ])),
      );

  Widget _chip(String label, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(docRadiusPill)),
        child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 11.5)),
      );

  Widget _errorBanner(String msg) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(color: docDangerBg, borderRadius: BorderRadius.circular(docRadiusSm)),
          child: Text(msg, style: const TextStyle(color: docDanger, fontSize: 12.5)),
        ),
      );

  Widget _actionCard({required String title, required String body, String? button, VoidCallback? onPressed}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: DocCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
            const SizedBox(height: 6),
            Text(body, style: const TextStyle(color: docMuted, fontSize: 12.5)),
            if (button != null) ...[
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: onPressed, child: Text(button))),
            ],
          ]),
        ),
      );

  Future<void> _requestConsent(String method) async {
    final res = await _act(() => context.read<AuthProvider>().api.requestConsent(widget.appointmentId, method));
    if (res is Map && res['otp'] != null) setState(() => _lastOtp = res['otp']);
  }

  Future<void> _resend(String method) async {
    final res = await _act(() => context.read<AuthProvider>().api.resendConsent(widget.appointmentId, method));
    if (res is Map && res['otp'] != null) setState(() => _lastOtp = res['otp']);
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  String _cap(String? s) => s == null || s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1);
}
