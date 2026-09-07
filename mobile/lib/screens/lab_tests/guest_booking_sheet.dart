import 'package:flutter/material.dart';
import '../../theme.dart';

/// "No, just book a test" path — enough to label a booking, no family member profile created.
/// Pops with {name, age, mobile} for the caller to attach to the lab-test booking.
class GuestBookingSheet extends StatefulWidget {
  const GuestBookingSheet({super.key});
  @override
  State<GuestBookingSheet> createState() => _GuestBookingSheetState();
}

class _GuestBookingSheetState extends State<GuestBookingSheet> {
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _mobile = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _mobile.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Full name is required')));
      return;
    }
    Navigator.of(context).pop({
      'guest_name': _name.text.trim(),
      'guest_age': int.tryParse(_age.text.trim()),
      'guest_mobile': _mobile.text.trim().isEmpty ? null : _mobile.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 18, right: 18, top: 12, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: careloopBorder, borderRadius: BorderRadius.circular(999)))),
            const SizedBox(height: 16),
            Text('Book for someone else', style: careloopSectionHeading().copyWith(fontSize: 18)),
            const SizedBox(height: 4),
            const Text("Just enough to label the booking — no profile is created, and nothing here becomes part of your family's health records.", style: TextStyle(color: careloopMuted, fontSize: 11.5)),
            const SizedBox(height: 16),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name')),
            const SizedBox(height: 10),
            TextField(controller: _age, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Age')),
            const SizedBox(height: 10),
            TextField(controller: _mobile, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number (for the lab to reach them)')),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: careloopNewBg, borderRadius: BorderRadius.circular(16)),
              child: const Row(children: [
                Icon(Icons.info_rounded, size: 18, color: careloopInfo),
                SizedBox(width: 10),
                Expanded(child: Text('You can always add them as a full family member later from the Family tab.', style: TextStyle(color: careloopInfo, fontSize: 12, fontWeight: FontWeight.w500))),
              ]),
            ),
            const SizedBox(height: 18),
            ElevatedButton(onPressed: _submit, child: const Text('Continue to tests')),
          ],
        ),
      ),
    );
  }
}
