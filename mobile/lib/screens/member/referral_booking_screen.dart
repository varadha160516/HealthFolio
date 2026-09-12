import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../auth_provider.dart';
import '../../theme.dart';

/// Fulfilling a doctor's referral — a lightweight, purpose-built booking flow (rather than the
/// full Appointments tab, which is a persistent bottom-nav page with no way to pass it context)
/// that either goes straight to date/time if the referring doctor named a specific specialist, or
/// offers a specialty-filtered doctor list first. Booking here tags the new appointment with
/// referral_id, which is what lets the receiving doctor's own pre-visit brief carry this
/// referral's reason and notes forward once THEIR consent unlocks.
class ReferralBookingScreen extends StatefulWidget {
  final Map<String, dynamic> referral;
  final String memberId;
  const ReferralBookingScreen({super.key, required this.referral, required this.memberId});

  @override
  State<ReferralBookingScreen> createState() => _ReferralBookingScreenState();
}

class _ReferralBookingScreenState extends State<ReferralBookingScreen> {
  List<dynamic>? _doctors;
  Map<String, dynamic>? _selectedProvider;
  DateTime? _datetime;
  final _reasonForVisit = TextEditingController();
  bool _booking = false;

  bool get _hasSpecificProvider => widget.referral['target_provider_id'] != null;

  @override
  void initState() {
    super.initState();
    _reasonForVisit.text = widget.referral['reason'] as String? ?? '';
    if (_hasSpecificProvider) {
      _selectedProvider = {
        'id': widget.referral['target_provider_id'],
        'name': widget.referral['target_provider_name'],
        'specialty': widget.referral['target_provider_specialty'],
      };
    } else {
      _loadDoctors();
    }
  }

  Future<void> _loadDoctors() async {
    final api = context.read<AuthProvider>().api;
    final all = await api.getProviders();
    final specialty = widget.referral['target_specialty'] as String?;
    if (mounted) setState(() => _doctors = specialty == null ? all : all.where((p) => p['specialty'] == specialty).toList());
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)), initialDate: DateTime.now());
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    setState(() => _datetime = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _confirm() async {
    if (_selectedProvider == null || _datetime == null) return;
    setState(() => _booking = true);
    try {
      final api = context.read<AuthProvider>().api;
      await api.bookAppointment({
        'member_id': widget.memberId,
        'provider_id': _selectedProvider!['id'],
        'datetime': _datetime!.toIso8601String(),
        'sharing_preference': 'full_history',
        'reason_for_visit': _reasonForVisit.text.trim().isEmpty ? null : _reasonForVisit.text.trim(),
        'referral_id': widget.referral['id'],
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final referringName = widget.referral['referring_provider_name'] as String? ?? 'Your doctor';
    final isUrgent = widget.referral['urgency'] == 'urgent';

    return Scaffold(
      backgroundColor: careloopBg,
      appBar: AppBar(title: const Text('Book referred visit')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: careloopAccentLight, borderRadius: BorderRadius.circular(careloopRadiusMd)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('Referred by $referringName', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: careloopAccentDark))),
                if (isUrgent)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: careloopDanger, borderRadius: BorderRadius.circular(999)),
                    child: const Text('Urgent', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 9.5)),
                  ),
              ]),
              const SizedBox(height: 4),
              Text(widget.referral['reason'] ?? '', style: const TextStyle(fontSize: 12.5, color: careloopAccentDark)),
            ]),
          ),
          const SizedBox(height: 18),
          if (_hasSpecificProvider) ...[
            const Text('SPECIALIST', style: TextStyle(fontSize: 10, color: careloopMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_selectedProvider!['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    Text(_selectedProvider!['specialty'] ?? '', style: const TextStyle(color: careloopMuted, fontSize: 11.5)),
                  ]),
                ),
              ]),
            ),
          ] else ...[
            const Text('CHOOSE A SPECIALIST', style: TextStyle(fontSize: 10, color: careloopMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            const SizedBox(height: 8),
            if (_doctors == null)
              const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator(color: careloopPrimary)))
            else if (_doctors!.isEmpty)
              const Text('No doctors found for this specialty yet.', style: TextStyle(color: careloopMuted, fontSize: 12.5))
            else
              for (final p in _doctors!.cast<Map<String, dynamic>>())
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(careloopRadiusMd),
                    onTap: () => setState(() => _selectedProvider = p),
                    child: Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: p['id'] == _selectedProvider?['id'] ? careloopAccentLight : careloopSurface,
                        borderRadius: BorderRadius.circular(careloopRadiusMd),
                        border: careloopCardBorder,
                        boxShadow: careloopCardShadow,
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            Text([p['specialty'], p['clinic_name']].where((v) => v != null).join(' · '), style: const TextStyle(color: careloopMuted, fontSize: 11.5)),
                          ]),
                        ),
                        if (p['id'] == _selectedProvider?['id']) const Icon(Icons.check_circle_rounded, color: careloopAccent),
                      ]),
                    ),
                  ),
                ),
          ],
          const SizedBox(height: 18),
          const Text('DATE & TIME', style: TextStyle(fontSize: 10, color: careloopMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_rounded, size: 16),
            label: Text(_datetime == null ? 'Choose date & time' : DateFormat('MMM d, yyyy · h:mm a').format(_datetime!)),
            onPressed: _pickDateTime,
          ),
          const SizedBox(height: 18),
          const Text('REASON FOR VISIT', style: TextStyle(fontSize: 10, color: careloopMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
          const SizedBox(height: 8),
          TextField(controller: _reasonForVisit, decoration: const InputDecoration(hintText: 'Why you are visiting')),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_selectedProvider == null || _datetime == null || _booking) ? null : _confirm,
              child: _booking ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : const Text('Confirm booking'),
            ),
          ),
        ],
      ),
    );
  }
}
