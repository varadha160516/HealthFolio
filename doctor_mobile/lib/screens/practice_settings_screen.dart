import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';

const _weekdayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

/// Back-office basics: default consultation fee (prefills, never forces, the per-visit fee
/// prompt on Complete Visit) and real weekly hours / leave days, which new bookings from
/// HealthFolio are now actually checked against server-side.
class PracticeSettingsScreen extends StatefulWidget {
  const PracticeSettingsScreen({super.key});
  @override
  State<PracticeSettingsScreen> createState() => _PracticeSettingsScreenState();
}

class _PracticeSettingsScreenState extends State<PracticeSettingsScreen> {
  Map<String, dynamic>? _profile;
  List<dynamic>? _availability;
  List<dynamic>? _timeOff;
  final _feeController = TextEditingController();
  bool _savingFee = false;
  final _registrationController = TextEditingController();
  final _qualificationsController = TextEditingController();
  final _experienceController = TextEditingController();
  bool _savingCredentials = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final results = await Future.wait([api.getMyProfile(), api.getAvailability(), api.getTimeOff()]);
    if (mounted) {
      setState(() {
        _profile = results[0] as Map<String, dynamic>;
        _availability = results[1] as List<dynamic>;
        _timeOff = results[2] as List<dynamic>;
        _feeController.text = (_profile!['default_fee'] as num?)?.toStringAsFixed(0) ?? '';
        _registrationController.text = _profile!['registration_number'] as String? ?? '';
        _qualificationsController.text = _profile!['qualifications'] as String? ?? '';
        _experienceController.text = (_profile!['years_of_experience'] as num?)?.toStringAsFixed(0) ?? '';
      });
    }
  }

  Future<void> _saveFee() async {
    final fee = double.tryParse(_feeController.text.trim());
    if (fee == null || fee < 0) return;
    setState(() => _savingFee = true);
    try {
      await context.read<AuthProvider>().api.updateDefaultFee(fee);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Default fee saved')));
    } finally {
      if (mounted) setState(() => _savingFee = false);
    }
  }

  // Self-declared, not verified against any medical council registry — a display field for the
  // doctor's own records, same trust level as the rest of this demo app's data.
  Future<void> _saveCredentials() async {
    final years = _experienceController.text.trim().isEmpty ? null : int.tryParse(_experienceController.text.trim());
    if (_experienceController.text.trim().isNotEmpty && (years == null || years < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Years of experience must be a whole number')));
      return;
    }
    setState(() => _savingCredentials = true);
    try {
      await context.read<AuthProvider>().api.updateCredentials(
            registrationNumber: _registrationController.text.trim().isEmpty ? null : _registrationController.text.trim(),
            qualifications: _qualificationsController.text.trim().isEmpty ? null : _qualificationsController.text.trim(),
            yearsOfExperience: years,
          );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Credentials saved')));
    } finally {
      if (mounted) setState(() => _savingCredentials = false);
    }
  }

  Future<void> _addAvailability() async {
    int day = DateTime.now().weekday % 7;
    TimeOfDay start = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay end = const TimeOfDay(hour: 17, minute: 0);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Add working hours'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownButtonFormField<int>(
              initialValue: day,
              decoration: const InputDecoration(labelText: 'Day'),
              items: [for (var i = 0; i < 7; i++) DropdownMenuItem(value: i, child: Text(_weekdayNames[i]))],
              onChanged: (v) => setDialogState(() => day = v ?? day),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final picked = await showTimePicker(context: dialogContext, initialTime: start);
                    if (picked != null) setDialogState(() => start = picked);
                  },
                  child: Text('From ${start.format(dialogContext)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final picked = await showTimePicker(context: dialogContext, initialTime: end);
                    if (picked != null) setDialogState(() => end = picked);
                  },
                  child: Text('To ${end.format(dialogContext)}'),
                ),
              ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    String fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    try {
      await context.read<AuthProvider>().api.addAvailability(dayOfWeek: day, startTime: fmt(start), endTime: fmt(end));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _removeAvailability(String id) async {
    await context.read<AuthProvider>().api.deleteAvailability(id);
    _load();
  }

  Future<void> _addTimeOff() async {
    final date = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)), initialDate: DateTime.now());
    if (date == null || !mounted) return;
    final dateStr = date.toIso8601String().substring(0, 10);
    await context.read<AuthProvider>().api.addTimeOff(date: dateStr);
    _load();
  }

  Future<void> _removeTimeOff(String id) async {
    await context.read<AuthProvider>().api.deleteTimeOff(id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_profile == null) return const DocGradientScaffold(body: LoadingCenter());
    final byDay = <int, List<Map<String, dynamic>>>{};
    for (final a in _availability!.cast<Map<String, dynamic>>()) {
      byDay.putIfAbsent(a['day_of_week'] as int, () => []).add(a);
    }

    return DocGradientScaffold(
      appBar: AppBar(title: const Text('Practice settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const Text('CREDENTIALS', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
          const SizedBox(height: 8),
          DocCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Self-declared for your own records — shown on your profile, not verified against any registry.', style: TextStyle(fontSize: 12, color: docMuted)),
              const SizedBox(height: 10),
              TextField(controller: _registrationController, decoration: const InputDecoration(labelText: 'Medical registration number')),
              const SizedBox(height: 10),
              TextField(controller: _qualificationsController, decoration: const InputDecoration(labelText: 'Qualifications', hintText: 'e.g. MBBS, MD (General Medicine)')),
              const SizedBox(height: 10),
              TextField(controller: _experienceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Years of experience')),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _savingCredentials ? null : _saveCredentials, child: const Text('Save credentials'))),
            ]),
          ),
          const SizedBox(height: 20),
          const Text('DEFAULT CONSULTATION FEE', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
          const SizedBox(height: 8),
          DocCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Prefills the fee prompt on Complete Visit — still editable per visit.', style: TextStyle(fontSize: 12, color: docMuted)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: _feeController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Fee (₹)', prefixText: '₹ '))),
                const SizedBox(width: 10),
                ElevatedButton(onPressed: _savingFee ? null : _saveFee, child: const Text('Save')),
              ]),
            ]),
          ),
          const SizedBox(height: 20),
          Row(children: [
            const Expanded(child: Text('WORKING HOURS', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4))),
            TextButton.icon(onPressed: _addAvailability, icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Add')),
          ]),
          if (_availability!.isEmpty)
            DocCard(child: const Text('No hours set — bookings are unrestricted until you add some.', style: TextStyle(fontSize: 12.5, color: docMuted)))
          else
            for (var day = 0; day < 7; day++)
              if (byDay.containsKey(day))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DocCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_weekdayNames[day], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 6),
                      for (final w in byDay[day]!)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(children: [
                            Expanded(child: Text('${w['start_time']} – ${w['end_time']}', style: const TextStyle(fontSize: 12.5))),
                            InkWell(onTap: () => _removeAvailability(w['id'] as String), child: const Icon(Icons.close_rounded, size: 16, color: docMutedDim)),
                          ]),
                        ),
                    ]),
                  ),
                ),
          const SizedBox(height: 20),
          Row(children: [
            const Expanded(child: Text('TIME OFF', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4))),
            TextButton.icon(onPressed: _addTimeOff, icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Add')),
          ]),
          if (_timeOff!.isEmpty)
            DocCard(child: const Text('No leave days added.', style: TextStyle(fontSize: 12.5, color: docMuted)))
          else
            for (final t in _timeOff!.cast<Map<String, dynamic>>())
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DocCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Expanded(child: Text(DateFormat('EEEE, MMM d, yyyy').format(DateTime.parse(t['date'] as String)), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                    InkWell(onTap: () => _removeTimeOff(t['id'] as String), child: const Icon(Icons.close_rounded, size: 16, color: docMutedDim)),
                  ]),
                ),
              ),
        ],
      ),
    );
  }
}
