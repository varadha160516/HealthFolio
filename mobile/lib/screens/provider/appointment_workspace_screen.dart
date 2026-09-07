import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api_client.dart';
import '../../auth_provider.dart';
import '../../theme.dart';
import '../../utils/range_format.dart';
import '../../widgets/glass.dart';
import '../../widgets/section_card.dart';

const _waitingStates = {'scheduled', 'checked_in', 'consent_requested'};

class AppointmentWorkspaceScreen extends StatefulWidget {
  final String appointmentId;
  const AppointmentWorkspaceScreen({super.key, required this.appointmentId});
  @override
  State<AppointmentWorkspaceScreen> createState() => _AppointmentWorkspaceScreenState();
}

class _AppointmentWorkspaceScreenState extends State<AppointmentWorkspaceScreen> {
  Map<String, dynamic>? _appt;
  Timer? _poll;
  String? _error;
  String? _lastOtp;
  String? _previsitBrief;
  bool _previsitLoading = false;
  final _otpInput = TextEditingController();
  final _diagnosis = TextEditingController();
  final List<Map<String, TextEditingController>> _lineItems = [_newLineItem()];

  static Map<String, TextEditingController> _newLineItem() => {
        'medicine_name': TextEditingController(),
        'dosage': TextEditingController(),
        'frequency': TextEditingController(),
      };

  ApiClient get _api => context.read<AuthProvider>().api;

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
    final data = await _api.getAppointment(widget.appointmentId);
    if (!mounted) return;
    setState(() => _appt = data);
    _poll?.cancel();
    if (_waitingStates.contains(data['status'])) {
      _poll = Timer(const Duration(seconds: 2), _load); // live status poll while waiting on consent
    } else if (data['status'] == 'consent_granted' || data['status'] == 'in_consultation') {
      _loadPrevisitBrief();
    }
  }

  /// Pre-visit prep agent (Roadmap Section 2.6) — fetched once access unlocks, cached client-side
  /// for the life of this screen. Fails silently: the raw unlocked-data panels below still show
  /// everything a doctor needs even if this drafted brief doesn't load.
  Future<void> _loadPrevisitBrief() async {
    if (_previsitBrief != null || _previsitLoading) return;
    setState(() => _previsitLoading = true);
    try {
      final r = await _api.getPrevisitBrief(widget.appointmentId);
      if (mounted) setState(() => _previsitBrief = r['brief'] as String);
    } catch (_) {
      // silent — see doc comment above
    } finally {
      if (mounted) setState(() => _previsitLoading = false);
    }
  }

  Future<dynamic> _act(Future<dynamic> Function() fn) async {
    setState(() => _error = null);
    try {
      final res = await fn();
      await _load();
      return res;
    } catch (e) {
      setState(() => _error = e.toString());
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_appt == null) return const GlassScaffold(body: Center(child: CircularProgressIndicator(color: careloopPrimary)));
    final status = _appt!['status'] as String;
    final unlocked = status == 'consent_granted' || status == 'in_consultation';
    final grant = _appt!['consentGrant'] as Map<String, dynamic>?;

    return GlassScaffold(
      appBar: GlassAppBar(title: Text(_appt!['member']?['name'] ?? '')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_appt!['datetime'].toString().substring(0, 16).replaceAll('T', ' '), style: const TextStyle(color: careloopMuted)),
              StatusPill.forAppointmentStatus(status),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null) InfoBanner(_error!),

          if (status == 'scheduled')
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Grants no data access — only makes the consent-request action available (Section 7.1).', style: TextStyle(color: careloopMuted, fontSize: 13)),
                  const SizedBox(height: 10),
                  ElevatedButton(onPressed: () => _act(() => _api.checkIn(widget.appointmentId)), child: const Text('Check in')),
                ],
              ),
            ),

          if (status == 'checked_in')
            SectionCard(
              title: 'Request consent for this visit',
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                ElevatedButton(
                  onPressed: () async {
                    final res = await _act(() => _api.requestConsent(widget.appointmentId, 'in_app'));
                    if (res != null && res['otp'] != null) setState(() => _lastOtp = res['otp']);
                  },
                  child: const Text('Send in-app request'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final res = await _act(() => _api.requestConsent(widget.appointmentId, 'otp'));
                    if (res != null && res['otp'] != null) setState(() => _lastOtp = res['otp']);
                  },
                  child: const Text('Use OTP fallback'),
                ),
              ]),
            ),

          if (status == 'consent_requested')
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InfoBanner(
                    'Waiting for the patient to respond (${grant?['method'] == 'otp' ? 'OTP fallback' : 'in-app'}) — expires '
                    '${grant?['expires_at'] != null ? DateTime.parse(grant!['expires_at']).toLocal().toString().substring(11, 16) : ''}. '
                    'The doctor must explicitly resend, never wait indefinitely (Section 7.1).',
                    info: true,
                  ),
                  if (grant?['method'] == 'otp') ...[
                    Row(children: [
                      Expanded(child: TextField(controller: _otpInput, decoration: const InputDecoration(hintText: '6-digit code read aloud by patient'))),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => _act(() => _api.verifyOtp(widget.appointmentId, _otpInput.text.trim())),
                        child: const Text('Verify'),
                      ),
                    ]),
                    const SizedBox(height: 8),
                  ],
                  if (_lastOtp != null) Text('(demo only — no real SMS wired up — code sent was $_lastOtp)', style: const TextStyle(color: careloopMuted, fontSize: 12)),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () async {
                      final res = await _act(() => _api.resendConsent(widget.appointmentId, grant?['method'] == 'otp' ? 'otp' : 'in_app'));
                      if (res != null && res['otp'] != null) setState(() => _lastOtp = res['otp']);
                    },
                    child: const Text('Resend request'),
                  ),
                ],
              ),
            ),

          if (status == 'consent_denied' || status == 'consent_expired')
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InfoBanner(status == 'consent_denied' ? 'The patient denied this consent request.' : 'The consent request expired without a response.'),
                  OutlinedButton(onPressed: () => _act(() => _api.resendConsent(widget.appointmentId, 'in_app')), child: const Text('Resend request')),
                ],
              ),
            ),

          if (unlocked && grant?['granted_at'] != null)
            InfoBanner('Access granted at ${DateTime.parse(grant!['granted_at']).toLocal()} · scope: ${grant['scope']}', info: true),

          if (unlocked && (_previsitLoading || _previsitBrief != null))
            SectionCard(
              title: 'Pre-visit brief',
              icon: Icons.summarize_rounded,
              child: _previsitLoading && _previsitBrief == null
                  ? const Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: careloopPrimary)),
                      SizedBox(width: 10),
                      Text('Reviewing flagged history…', style: TextStyle(color: careloopMuted, fontSize: 13)),
                    ])
                  : Text(_previsitBrief ?? '', style: const TextStyle(color: careloopTextPrimary, fontSize: 14, height: 1.5)),
            ),

          if (unlocked && _appt!['unlockedData'] != null) ..._buildUnlockedData(_appt!['unlockedData']),

          if (status == 'consent_granted')
            SectionCard(child: ElevatedButton(onPressed: () => _act(() => _api.startConsultation(widget.appointmentId)), child: const Text('Begin consultation'))),

          if (status == 'in_consultation') _buildConsultation(),

          if (status == 'completed')
            const SectionCard(child: Text("Visit completed — access to this patient's records was revoked immediately (Section 7.1).")),
        ],
      ),
    );
  }

  List<Widget> _buildUnlockedData(Map<String, dynamic> data) {
    final summary = data['summary'] as Map<String, dynamic>;
    final flagged = data['flaggedHistory'] as List<dynamic>;
    final docs = data['documents'] as List<dynamic>;
    return [
      SectionCard(
        title: 'Allergies & conditions',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Allergies: ${(summary['allergies'] as List).map((a) => a['value']).join(', ').ifEmpty('None')}'),
            Text('Chronic conditions: ${(summary['chronicConditions'] as List).map((c) => c['value']).join(', ').ifEmpty('None')}'),
            Text('Current medications: ${(summary['currentMedications'] as List).map((m) => m['medicine_name']).join(', ').ifEmpty('None')}'),
          ],
        ),
      ),
      SectionCard(
        title: 'Flagged — out of range',
        child: flagged.isEmpty
            ? const Text('Nothing flagged.', style: TextStyle(color: careloopMuted))
            : Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(flex: 3, child: Text('PARAMETER', style: TextStyle(color: careloopMuted, fontWeight: FontWeight.w600, fontSize: 11))),
                      Expanded(flex: 2, child: Text('VALUE', style: TextStyle(color: careloopMuted, fontWeight: FontWeight.w600, fontSize: 11))),
                      Expanded(flex: 2, child: Text('RANGE', style: TextStyle(color: careloopMuted, fontWeight: FontWeight.w600, fontSize: 11))),
                    ]),
                  ),
                  for (final f in flagged.cast<Map<String, dynamic>>())
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Expanded(flex: 3, child: Text(f['display_name'], style: const TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(
                          flex: 2,
                          child: Text('${f['canonical_value']} ${f['canonical_unit'] ?? ''}'.trim(), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            formatReferenceRange(f['range_type'], f['resolved_reference_range'] as Map<String, dynamic>?).ifEmpty('—'),
                            style: const TextStyle(color: careloopMuted, fontSize: 12),
                          ),
                        ),
                      ]),
                    ),
                ],
              ),
      ),
      SectionCard(
        title: 'Document timeline',
        child: Column(
          children: [
            for (final d in docs)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text((d['document_type'] as String).replaceAll('_', ' ')),
                subtitle: Text('${d['source_lab_name'] ?? '—'} · ${d['test_date'] ?? (d['upload_date'] as String).substring(0, 10)}'),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _buildConsultation() {
    return SectionCard(
      title: 'e-Prescription',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(controller: _diagnosis, decoration: const InputDecoration(labelText: 'Diagnosis')),
          const SizedBox(height: 10),
          for (var i = 0; i < _lineItems.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(children: [
                TextField(controller: _lineItems[i]['medicine_name'], decoration: const InputDecoration(labelText: 'Medicine')),
                const SizedBox(height: 6),
                TextField(controller: _lineItems[i]['dosage'], decoration: const InputDecoration(labelText: 'Dosage (e.g. 500mg)')),
                const SizedBox(height: 6),
                TextField(controller: _lineItems[i]['frequency'], decoration: const InputDecoration(labelText: 'Frequency / duration')),
              ]),
            ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: () => setState(() => _lineItems.add(_newLineItem())), child: const Text('+ Add medicine')),
            ElevatedButton(onPressed: _issuePrescription, child: const Text('Sign & issue prescription')),
          ]),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => _act(() => _api.completeVisit(widget.appointmentId)),
            style: OutlinedButton.styleFrom(foregroundColor: careloopPrimaryDark),
            child: const Text('Complete visit'),
          ),
        ],
      ),
    );
  }

  Future<void> _issuePrescription() async {
    final items = _lineItems
        .where((li) => li['medicine_name']!.text.trim().isNotEmpty)
        .map((li) => {
              'medicine_name': li['medicine_name']!.text.trim(),
              'dosage': li['dosage']!.text.trim(),
              'frequency': li['frequency']!.text.trim(),
            })
        .toList();
    if (items.isEmpty) return;

    // Medication reconciliation agent (Roadmap Section 2.7) — advisory only. It never blocks
    // signing; "Sign anyway" is always available right alongside the flags.
    try {
      final flags = await _api.reconcileDraft(widget.appointmentId, items);
      if (flags.isNotEmpty && mounted) {
        final proceed = await _showReconciliationDialog(flags.cast<Map<String, dynamic>>());
        if (proceed != true) return;
      }
    } catch (_) {
      // Reconciliation is a courtesy check — if it fails to load, fall through and let the
      // doctor sign as normal rather than blocking on it.
    }

    await _act(() => _api.issuePrescription(widget.appointmentId, {'diagnosis_text': _diagnosis.text.trim(), 'line_items': items}));
    setState(() {
      _lineItems
        ..clear()
        ..add(_newLineItem());
      _diagnosis.clear();
    });
  }

  Future<bool?> _showReconciliationDialog(List<Map<String, dynamic>> flags) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Worth a second look'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final f in flags)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(f['kind'] == 'allergy_conflict' ? Icons.warning_rounded : Icons.content_copy_rounded, size: 17, color: careloopWarning),
                  const SizedBox(width: 8),
                  Expanded(child: Text(f['message'] ?? '', style: const TextStyle(fontSize: 13.5, height: 1.35))),
                ]),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Review')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign anyway')),
        ],
      ),
    );
  }
}

extension _IfEmpty on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
