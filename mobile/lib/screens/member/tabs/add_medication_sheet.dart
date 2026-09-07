import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';

const _kFrequencyPresets = <(String, String, List<String>)>[
  ('Once daily', 'daily', ['08:00']),
  ('Twice daily', 'daily', ['08:00', '20:00']),
  ('Three times daily', 'daily', ['08:00', '14:00', '20:00']),
  ('Weekly', 'weekly', ['20:00']),
  ('As needed', 'as_needed', []),
];

/// Manual add — and, when [scheduleId] is passed, edit — for a medication schedule. Frequency
/// picks from a small set of presets (times snap to 8/2/8 defaults) rather than a full per-dose
/// time picker, to keep the form to one screen; a real v2 would let each dose time be tuned
/// independently.
class AddMedicationSheet extends StatefulWidget {
  final String memberId;
  final String? scheduleId;
  final Map<String, dynamic>? initial;
  const AddMedicationSheet({super.key, required this.memberId, this.scheduleId, this.initial});

  @override
  State<AddMedicationSheet> createState() => _AddMedicationSheetState();
}

class _AddMedicationSheetState extends State<AddMedicationSheet> {
  late final TextEditingController _name;
  late final TextEditingController _strength;
  late final TextEditingController _doseAmount;
  late final TextEditingController _prescribedBy;
  late final TextEditingController _purpose;
  late final TextEditingController _startDate;
  late final TextEditingController _endDate;
  int _presetIndex = 0;
  int _dayOfWeek = DateTime.now().weekday % 7;
  bool _busy = false;

  static const _weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

  @override
  void initState() {
    super.initState();
    final m = widget.initial;
    _name = TextEditingController(text: m?['medicine_name'] ?? '');
    _strength = TextEditingController(text: m?['strength'] ?? '');
    _doseAmount = TextEditingController(text: m?['dose_amount'] ?? '1 tablet');
    _prescribedBy = TextEditingController(text: m?['prescribed_by'] ?? '');
    _purpose = TextEditingController(text: m?['purpose'] ?? '');
    _startDate = TextEditingController(text: m?['start_date'] ?? DateTime.now().toIso8601String().substring(0, 10));
    _endDate = TextEditingController(text: m?['end_date'] ?? '');
    if (m != null) {
      final freq = m['frequency'] as String?;
      final times = (m['times'] as List?)?.cast<String>() ?? const [];
      _presetIndex = _kFrequencyPresets.indexWhere((p) => p.$2 == freq && p.$3.length == times.length);
      if (_presetIndex < 0) _presetIndex = 0;
      if (m['day_of_week'] != null) _dayOfWeek = m['day_of_week'] as int;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _strength.dispose();
    _doseAmount.dispose();
    _prescribedBy.dispose();
    _purpose.dispose();
    _startDate.dispose();
    _endDate.dispose();
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController c) async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(c.text.trim()) ?? now;
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(now.year - 2), lastDate: DateTime(now.year + 2));
    if (picked != null) setState(() => c.text = picked.toIso8601String().substring(0, 10));
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _startDate.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Medicine name and start date are required')));
      return;
    }
    setState(() => _busy = true);
    final preset = _kFrequencyPresets[_presetIndex];
    final payload = {
      'medicine_name': _name.text.trim(),
      'strength': _strength.text.trim().isEmpty ? null : _strength.text.trim(),
      'dose_amount': _doseAmount.text.trim().isEmpty ? null : _doseAmount.text.trim(),
      'frequency': preset.$2,
      'times': preset.$3,
      if (preset.$2 == 'weekly') 'day_of_week': _dayOfWeek,
      'start_date': _startDate.text.trim(),
      'end_date': _endDate.text.trim().isEmpty ? null : _endDate.text.trim(),
      'prescribed_by': _prescribedBy.text.trim().isEmpty ? null : _prescribedBy.text.trim(),
      'purpose': _purpose.text.trim().isEmpty ? null : _purpose.text.trim(),
    };
    try {
      final api = context.read<AuthProvider>().api;
      if (widget.scheduleId != null) {
        await api.updateMedication(widget.scheduleId!, payload);
      } else {
        await api.addMedication(widget.memberId, payload);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete medication?'),
        content: Text('This removes ${_name.text} and its dose history.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete', style: TextStyle(color: careloopDanger))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<AuthProvider>().api.deleteMedication(widget.scheduleId!);
      if (mounted) Navigator.of(context).pop('deleted');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.scheduleId != null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 18, right: 18, top: 12, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: careloopBorder, borderRadius: BorderRadius.circular(999)))),
              const SizedBox(height: 16),
              Text(isEdit ? 'Edit medication' : 'Add medication', style: careloopSectionHeading().copyWith(fontSize: 18)),
              const SizedBox(height: 16),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Medicine name')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: _strength, decoration: const InputDecoration(labelText: 'Strength (e.g. 40 mg)'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _doseAmount, decoration: const InputDecoration(labelText: 'Dose amount'))),
              ]),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _presetIndex,
                decoration: const InputDecoration(labelText: 'Frequency'),
                items: [for (var i = 0; i < _kFrequencyPresets.length; i++) DropdownMenuItem(value: i, child: Text(_kFrequencyPresets[i].$1))],
                onChanged: (v) => setState(() => _presetIndex = v ?? 0),
              ),
              if (_kFrequencyPresets[_presetIndex].$2 == 'weekly') ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _dayOfWeek,
                  decoration: const InputDecoration(labelText: 'Day of week'),
                  items: [for (var i = 0; i < _weekdays.length; i++) DropdownMenuItem(value: i, child: Text(_weekdays[i]))],
                  onChanged: (v) => setState(() => _dayOfWeek = v ?? _dayOfWeek),
                ),
              ],
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _startDate,
                    readOnly: true,
                    onTap: () => _pickDate(_startDate),
                    decoration: const InputDecoration(labelText: 'Start date', suffixIcon: Icon(Icons.calendar_month_rounded, size: 18)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _endDate,
                    readOnly: true,
                    onTap: () => _pickDate(_endDate),
                    decoration: const InputDecoration(labelText: 'End date (optional)', suffixIcon: Icon(Icons.calendar_month_rounded, size: 18)),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(controller: _prescribedBy, decoration: const InputDecoration(labelText: 'Prescribed by (optional)')),
              const SizedBox(height: 10),
              TextField(controller: _purpose, decoration: const InputDecoration(labelText: 'Purpose (optional)')),
              const SizedBox(height: 18),
              ElevatedButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : (isEdit ? 'Save changes' : 'Add medication'))),
              if (isEdit) ...[
                const SizedBox(height: 8),
                TextButton(onPressed: _busy ? null : _delete, child: const Text('Delete medication', style: TextStyle(color: careloopDanger))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
