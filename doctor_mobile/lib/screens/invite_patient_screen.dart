import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../api_client.dart';
import '../auth_provider.dart';
import '../services/external_link.dart';
import '../theme.dart';

/// Invite a patient to HealthFolio over WhatsApp. Nothing is sent from here: the app opens WhatsApp
/// on this phone with the message ready, and the person at the clinic taps send. The message carries a
/// one-time code, which is the only way to create a HealthFolio account — so the pilot stays invite-only,
/// and someone registered at the counter can claim the record the clinic already made for them.
class InvitePatientScreen extends StatefulWidget {
  /// Set when inviting someone the clinic just registered: the number comes from their record, and
  /// they'll claim that record when they join.
  final String? memberId;
  final String? name;
  final bool agreedPrefilled;
  const InvitePatientScreen({super.key, this.memberId, this.name, this.agreedPrefilled = false});
  @override
  State<InvitePatientScreen> createState() => _InvitePatientScreenState();
}

class _InvitePatientScreenState extends State<InvitePatientScreen> {
  final _phone = TextEditingController();
  late final _name = TextEditingController(text: widget.name ?? '');
  late bool _agreed = widget.agreedPrefilled;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _last;

  ApiClient get _api => context.read<AuthProvider>().api;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadSummary() async {
    try {
      final s = await _api.getInviteSummary();
      if (mounted) setState(() => _summary = s);
    } catch (_) {
      // The counters are a nicety; sending an invite doesn't depend on them.
    }
  }

  bool get _canSend => !_busy && _agreed && (widget.memberId != null || _phone.text.replaceAll(RegExp(r'\D'), '').length >= 10);

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
      _last = null;
    });
    try {
      final res = await _api.createInvite(
        phone: widget.memberId == null ? _phone.text.trim() : null,
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        memberId: widget.memberId,
        patientAgreed: _agreed,
      );
      if (!mounted) return;
      setState(() {
        _last = res;
        if (widget.memberId == null) {
          _phone.clear();
          _name.clear();
          _agreed = false;
        }
      });
      await openExternalLink(context, res['url'] as String, failure: "Couldn't open WhatsApp on this phone. Read the code below out to the patient instead.");
      await _loadSummary();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _stat(String label, int n, Color color) => Expanded(
        child: Column(children: [
          Text('$n', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(fontSize: 10.5, color: docMuted, fontWeight: FontWeight.w600)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final recent = ((_summary?['recent'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final claiming = widget.memberId != null;
    return DocGradientScaffold(
      appBar: AppBar(title: const Text('Invite to HealthFolio')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_summary != null)
            DocCard(
              child: Row(children: [
                _stat('Invited', _summary!['sent'] as int, docTextPrimary),
                _stat('Joined', _summary!['joined'] as int, docSuccess),
                _stat('Waiting', _summary!['pending'] as int, docWarning),
              ]),
            ),
          const SizedBox(height: 14),
          DocCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(claiming ? 'Invite ${widget.name ?? 'this patient'}' : 'Invite a patient', style: docSectionHeading().copyWith(fontSize: 16)),
              const SizedBox(height: 4),
              Text(
                claiming
                    ? "They'll get a WhatsApp message with a one-time code. When they join, they see the record you created for them today."
                    : "They'll get a WhatsApp message with a one-time code to install the app and create their account. Their records stay private — you only see them when they approve a visit.",
                style: const TextStyle(fontSize: 12, color: docMuted, height: 1.4),
              ),
              const SizedBox(height: 14),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: docDangerBg, borderRadius: BorderRadius.circular(docRadiusMd)),
                  child: Text(_error!, style: const TextStyle(color: docDanger, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              if (!claiming) ...[
                TextField(controller: _phone, keyboardType: TextInputType.phone, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Mobile number')),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _name,
                readOnly: claiming,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: claiming ? 'Patient' : "Patient's name (optional)"),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                value: _agreed,
                onChanged: (v) => setState(() => _agreed = v ?? false),
                title: const Text('This patient agreed to receive this invite', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                subtitle: const Text('Only invite people who asked for it or said yes when you offered.', style: TextStyle(fontSize: 11, color: docMuted)),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _canSend ? _send : null,
                icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.chat_rounded, size: 18),
                label: const Text('Send invite on WhatsApp'),
              ),
            ]),
          ),
          if (_last != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(color: docSuccessBg, borderRadius: BorderRadius.circular(docRadiusMd)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Invite ready in WhatsApp', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: docSuccess)),
                const SizedBox(height: 4),
                Text('Code ${_last!['code']} — works once, expires ${DateFormat('MMM d').format(DateTime.parse(_last!['expires_at'] as String).toLocal())}.', style: const TextStyle(fontSize: 12.5)),
                if (_last!['invited_before_at'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('You already invited this number on ${DateFormat('MMM d').format(DateTime.parse(_last!['invited_before_at'] as String).toLocal())}.', style: const TextStyle(fontSize: 11.5, color: docMuted)),
                  ),
              ]),
            ),
          ],
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text('RECENT INVITES', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            const SizedBox(height: 8),
            DocCard(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              child: Column(children: [
                for (var i = 0; i < recent.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text((recent[i]['name'] as String?) ?? 'Number ending ${recent[i]['phone_tail']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          Text('Sent ${DateFormat('MMM d').format(DateTime.parse(recent[i]['sent_at'] as String).toLocal())}${recent[i]['claims_existing_record'] == true ? ' · has a record here' : ''}',
                              style: const TextStyle(fontSize: 11, color: docMuted)),
                        ]),
                      ),
                      _statusChip(recent[i]['status'] as String),
                    ]),
                  ),
                ],
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final (label, fg, bg) = switch (status) {
      'joined' => ('Joined', docSuccess, docSuccessBg),
      'expired' => ('Expired', docMuted, docSurfaceRaised),
      _ => ('Waiting', docWarning, docWarningBg),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}
