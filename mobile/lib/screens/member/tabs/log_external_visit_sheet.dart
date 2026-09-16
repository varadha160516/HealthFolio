import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';

/// A member's own record of a visit to a doctor not on CareLoop — the realistic alternative to a
/// real external-EHR/ABDM integration. Purely self-declared; its value is that medications logged
/// from this visit (via the normal Add Medication flow, prescribed_by prefilled from here) feed
/// straight into the safety net's existing cross-provider checks, with no change to that logic.
class LogExternalVisitSheet extends StatefulWidget {
  final String memberId;
  const LogExternalVisitSheet({super.key, required this.memberId});
  @override
  State<LogExternalVisitSheet> createState() => _LogExternalVisitSheetState();
}

class _LogExternalVisitSheetState extends State<LogExternalVisitSheet> {
  final _doctorName = TextEditingController();
  final _hospitalName = TextEditingController();
  final _diagnosis = TextEditingController();
  final _notes = TextEditingController();
  final _visitDate = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _doctorName.dispose();
    _hospitalName.dispose();
    _diagnosis.dispose();
    _notes.dispose();
    _visitDate.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_visitDate.text.trim()) ?? now;
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(now.year - 5), lastDate: now);
    if (picked != null) setState(() => _visitDate.text = picked.toIso8601String().substring(0, 10));
  }

  Future<void> _save() async {
    if (_doctorName.text.trim().isEmpty) {
      setState(() => _error = 'Doctor name is required');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = context.read<AuthProvider>().api;
      final result = await api.addExternalVisit(widget.memberId, {
        'doctor_name': _doctorName.text.trim(),
        'hospital_name': _hospitalName.text.trim().isEmpty ? null : _hospitalName.text.trim(),
        'visit_date': _visitDate.text.trim(),
        'diagnosis': _diagnosis.text.trim().isEmpty ? null : _diagnosis.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (mounted) {
        Navigator.of(context).pop({
          'saved': true,
          'doctor_name': _doctorName.text.trim(),
          'hospital_name': _hospitalName.text.trim(),
          'diagnosis': _diagnosis.text.trim(),
          'id': result['id'],
        });
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 18, right: 18, top: 12, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: careloopBorder, borderRadius: BorderRadius.circular(999)))),
              const SizedBox(height: 16),
              Text('Log an outside visit', style: careloopSectionHeading().copyWith(fontSize: 18)),
              const SizedBox(height: 4),
              const Text(
                'For a doctor or hospital not on CareLoop. This helps your own Safety Check catch things like duplicate medications across providers.',
                style: TextStyle(color: careloopMuted, fontSize: 11.5, height: 1.4),
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: careloopAbnormalBg, borderRadius: BorderRadius.circular(careloopRadiusMd)),
                  child: Text(_error!, style: const TextStyle(color: careloopDanger, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 12),
              ],
              TextField(controller: _doctorName, decoration: const InputDecoration(labelText: 'Doctor name')),
              const SizedBox(height: 10),
              TextField(controller: _hospitalName, decoration: const InputDecoration(labelText: 'Hospital / clinic (optional)')),
              const SizedBox(height: 10),
              TextField(
                controller: _visitDate,
                readOnly: true,
                onTap: _pickDate,
                decoration: const InputDecoration(labelText: 'Visit date', suffixIcon: Icon(Icons.calendar_month_rounded, size: 18)),
              ),
              const SizedBox(height: 10),
              TextField(controller: _diagnosis, decoration: const InputDecoration(labelText: 'Diagnosis / reason (optional)')),
              const SizedBox(height: 10),
              TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (optional)')),
              const SizedBox(height: 18),
              ElevatedButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save visit')),
            ],
          ),
        ),
      ),
    );
  }
}
