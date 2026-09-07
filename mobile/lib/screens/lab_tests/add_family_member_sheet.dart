import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../auth_provider.dart';
import '../../theme.dart';
import '../../utils/blood_groups.dart';

/// Same fields and the same real api.addMember() call as the Family dashboard's inline "Add a
/// dependent" form (family_dashboard_screen.dart) — packaged as a bottom sheet instead, since
/// this is reached mid-flow from Lab Tests rather than from the Family tab itself. Ends with an
/// explicit consent dialog before the member is actually created, per the request.
class AddFamilyMemberSheet extends StatefulWidget {
  const AddFamilyMemberSheet({super.key});
  @override
  State<AddFamilyMemberSheet> createState() => _AddFamilyMemberSheetState();
}

class _AddFamilyMemberSheetState extends State<AddFamilyMemberSheet> {
  final _name = TextEditingController();
  final _dob = TextEditingController();
  String _relationship = 'child';
  String? _sex;
  String? _bloodGroup;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _dob.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_dob.text.trim()) ?? DateTime(now.year - 5);
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(1900), lastDate: now);
    if (picked != null) setState(() => _dob.text = picked.toIso8601String().substring(0, 10));
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Full name is required')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add to your family?'),
        content: const Text('This will create a family member profile that you can use to manage their lab bookings and health records.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Yes, add member')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final api = context.read<AuthProvider>().api;
      await api.addMember({
        'name': _name.text.trim(),
        'dob': _dob.text.trim().isEmpty ? null : _dob.text.trim(),
        'sex': _sex,
        'blood_group': _bloodGroup,
        'relationship_to_primary': _relationship,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
              Text('Add family member', style: careloopSectionHeading().copyWith(fontSize: 18)),
              const SizedBox(height: 4),
              const Text('Add them to your family so you can manage their health records and bookings in one place.', style: TextStyle(color: careloopMuted, fontSize: 11.5)),
              const SizedBox(height: 16),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _relationship,
                decoration: const InputDecoration(labelText: 'Relationship'),
                items: const [
                  DropdownMenuItem(value: 'spouse', child: Text('Spouse')),
                  DropdownMenuItem(value: 'child', child: Text('Child')),
                  DropdownMenuItem(value: 'parent', child: Text('Parent')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => setState(() => _relationship = v ?? 'child'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _dob,
                readOnly: true,
                onTap: _pickDob,
                decoration: const InputDecoration(labelText: 'Date of birth', suffixIcon: Icon(Icons.calendar_month_rounded, size: 18)),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _sex,
                decoration: const InputDecoration(labelText: 'Gender'),
                items: const [
                  DropdownMenuItem(value: 'female', child: Text('Female')),
                  DropdownMenuItem(value: 'male', child: Text('Male')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => setState(() => _sex = v),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _bloodGroup,
                decoration: const InputDecoration(labelText: 'Blood group (optional)'),
                items: [for (final g in kBloodGroups) DropdownMenuItem(value: g, child: Text(g))],
                onChanged: (v) => setState(() => _bloodGroup = v),
              ),
              const SizedBox(height: 18),
              ElevatedButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Adding…' : 'Add member')),
            ],
          ),
        ),
      ),
    );
  }
}
