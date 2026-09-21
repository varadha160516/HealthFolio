import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../api_client.dart';
import '../../auth_provider.dart';
import '../../theme.dart';

/// Checks in someone standing at the counter with no appointment. Find them by mobile number first
/// (they may already be on CareLoop — then their own app gets the normal consent prompt), or register
/// them here. Nothing about this unlocks a record: the doctor still requests access and the patient
/// still answers.
class WalkInSheet extends StatefulWidget {
  final List<(String, String)> doctors; // (provider id, name)
  const WalkInSheet({super.key, required this.doctors});
  @override
  State<WalkInSheet> createState() => _WalkInSheetState();
}

class _WalkInSheetState extends State<WalkInSheet> {
  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _reason = TextEditingController();
  final _dob = TextEditingController();
  String? _sex;
  bool _whatsappOptIn = false;
  late String _doctorId = widget.doctors.first.$1;

  List<Map<String, dynamic>>? _matches; // null = haven't searched yet
  String? _selectedMemberId;
  bool _registering = false;
  bool _busy = false;
  String? _error;
  // Server 409 detail we act on rather than just display.
  List<Map<String, dynamic>>? _duplicateMatches;
  Map<String, dynamic>? _existingVisit;

  ApiClient get _api => context.read<AuthProvider>().api;

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    _reason.dispose();
    _dob.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    setState(() {
      _busy = true;
      _error = null;
      _selectedMemberId = null;
      _duplicateMatches = null;
      _existingVisit = null;
    });
    try {
      final found = (await _api.frontDeskLookupPatient(_phone.text.trim())).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _matches = found;
        _registering = found.isEmpty;
        if (found.length == 1) _selectedMemberId = found.first['id'] as String;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(context: context, initialDate: DateTime(DateTime.now().year - 30), firstDate: DateTime(1900), lastDate: DateTime.now());
    if (picked != null) setState(() => _dob.text = DateFormat('yyyy-MM-dd').format(picked));
  }

  bool get _canSubmit => !_busy && (_registering ? _name.text.trim().length >= 2 && _phone.text.trim().isNotEmpty : _selectedMemberId != null);

  Future<void> _submit({bool confirmDuplicate = false, String? useMemberId}) async {
    setState(() {
      _busy = true;
      _error = null;
      _duplicateMatches = null;
      _existingVisit = null;
    });
    final memberId = useMemberId ?? (_registering ? null : _selectedMemberId);
    try {
      final res = await _api.frontDeskCreateWalkIn({
        'provider_id': _doctorId,
        // The clinic's own wall-clock now, in the same zone-less form member bookings use.
        'datetime': DateTime.now().toIso8601String(),
        if (_reason.text.trim().isNotEmpty) 'reason': _reason.text.trim(),
        if (memberId != null) 'member_id': memberId,
        if (memberId == null)
          'new_patient': {
            'name': _name.text.trim(),
            'phone': _phone.text.trim(),
            if (_sex != null) 'sex': _sex,
            if (_dob.text.isNotEmpty) 'dob': _dob.text,
            'whatsapp_opt_in': _whatsappOptIn,
          },
        if (confirmDuplicate) 'confirm_duplicate': true,
      });
      if (mounted) {
        Navigator.of(context).pop({
          'registered_new': res['registered_new'] == true,
          'member_id': res['member_id'],
          'name': _name.text.trim(),
          'whatsapp_opt_in': _whatsappOptIn,
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      final body = e.body;
      setState(() {
        if (e.status == 409 && body?['matches'] is List) {
          _duplicateMatches = (body!['matches'] as List).cast<Map<String, dynamic>>();
        } else if (e.status == 409 && body?['appointment_id'] != null) {
          _existingVisit = body;
        } else {
          _error = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkInExisting() async {
    setState(() => _busy = true);
    try {
      await _api.frontDeskCheckIn(_existingVisit!['appointment_id'] as String);
      if (mounted) Navigator.of(context).pop({'registered_new': false});
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _person(Map<String, dynamic> m) => '${m['name']}${m['age'] != null ? ' · ${m['age']}' : ''}';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 18, right: 18, top: 12, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: docBorder, borderRadius: BorderRadius.circular(999)))),
            const SizedBox(height: 14),
            Text('Walk-in patient', style: docSectionHeading().copyWith(fontSize: 18)),
            const SizedBox(height: 2),
            const Text('Checks them in with a token. The doctor still has to ask for access to their records.', style: TextStyle(color: docMuted, fontSize: 11.5, height: 1.4)),
            const SizedBox(height: 14),
            if (_error != null) _banner(_error!, docDangerBg, docDanger),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => setState(() {
                    _matches = null;
                    _selectedMemberId = null;
                  }),
                  decoration: const InputDecoration(labelText: 'Mobile number'),
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: OutlinedButton(onPressed: _busy || _phone.text.trim().length < 10 ? null : _find, child: const Text('Find')),
              ),
            ]),
            if (_matches != null && _matches!.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('ALREADY ON CARELOOP', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              for (final m in _matches!)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_selectedMemberId == m['id'] ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, color: _selectedMemberId == m['id'] ? docPrimary : docMuted, size: 20),
                  title: Text(_person(m), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  onTap: () => setState(() {
                    _selectedMemberId = m['id'] as String;
                    _registering = false;
                  }),
                ),
              TextButton(onPressed: () => setState(() {
                _registering = true;
                _selectedMemberId = null;
              }), child: const Text('None of these — register a new patient')),
            ],
            if (_matches != null && _matches!.isEmpty) ...[
              const SizedBox(height: 8),
              const Text('Not on CareLoop yet — register them below.', style: TextStyle(fontSize: 12, color: docMuted)),
            ],
            if (_registering) ...[
              const SizedBox(height: 10),
              TextField(controller: _name, textCapitalization: TextCapitalization.words, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Full name')),
              const SizedBox(height: 10),
              Row(children: [
                for (final s in const ['male', 'female', 'other'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(s[0].toUpperCase() + s.substring(1)), selected: _sex == s, onSelected: (v) => setState(() => _sex = v ? s : null)),
                  ),
              ]),
              const SizedBox(height: 6),
              TextField(controller: _dob, readOnly: true, onTap: _pickDob, decoration: const InputDecoration(labelText: 'Date of birth (optional)', suffixIcon: Icon(Icons.calendar_month_rounded, size: 18))),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                value: _whatsappOptIn,
                onChanged: (v) => setState(() => _whatsappOptIn = v ?? false),
                title: const Text('They agree to WhatsApp updates', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                subtitle: const Text('Token and reminder nudges only — nothing about their health. Ask first.', style: TextStyle(fontSize: 11, color: docMuted)),
              ),
            ],
            if (_registering || _selectedMemberId != null) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _doctorId,
                decoration: const InputDecoration(labelText: 'See which doctor?'),
                items: [for (final d in widget.doctors) DropdownMenuItem(value: d.$1, child: Text(d.$2))],
                onChanged: (v) => setState(() => _doctorId = v ?? _doctorId),
              ),
              const SizedBox(height: 10),
              TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Reason for visit (optional)')),
            ],
            if (_duplicateMatches != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: docWarningBg, borderRadius: BorderRadius.circular(docRadiusMd)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Someone is already registered with this number', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: docWarning)),
                  const SizedBox(height: 6),
                  for (final m in _duplicateMatches!)
                    Row(children: [
                      Expanded(child: Text(_person(m), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                      TextButton(onPressed: _busy ? null : () => _submit(useMemberId: m['id'] as String), child: const Text('It\'s them')),
                    ]),
                  const Divider(height: 14),
                  const Text('Family members often share a phone.', style: TextStyle(fontSize: 11, color: docMuted)),
                  TextButton(onPressed: _busy ? null : () => _submit(confirmDuplicate: true), child: const Text('This is a different person — register them')),
                ]),
              ),
            ],
            if (_existingVisit != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: docInfoBg, borderRadius: BorderRadius.circular(docRadiusMd)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_existingVisit!['error'] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: docInfo)),
                  if (_existingVisit!['appointment_status'] == 'scheduled')
                    TextButton(onPressed: _busy ? null : _checkInExisting, child: const Text('Check in that appointment instead'))
                  else
                    const Text('They are already checked in.', style: TextStyle(fontSize: 11.5, color: docMuted)),
                ]),
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _canSubmit ? () => _submit() : null,
              child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Check in walk-in'),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _banner(String text, Color bg, Color fg) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(docRadiusMd)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
      );
}
