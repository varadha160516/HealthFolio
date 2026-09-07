import 'package:flutter/material.dart';
import '../../theme.dart';

/// "Add a new family member" decision — pops 'family' or 'guest' (or null on dismiss/cancel).
class AddSomeoneNewSheet extends StatelessWidget {
  const AddSomeoneNewSheet({super.key});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: careloopBorder, borderRadius: BorderRadius.circular(999)))),
            const SizedBox(height: 16),
            Text('Add someone new', style: careloopSectionHeading().copyWith(fontSize: 18), textAlign: TextAlign.center),
            const Text('Is this person okay to be added to your family?', style: TextStyle(color: careloopMuted, fontSize: 12), textAlign: TextAlign.center),
            const SizedBox(height: 18),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.of(context).pop('family'),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: careloopAccentLight, borderRadius: BorderRadius.circular(16)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.check_circle_rounded, color: careloopAccent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Yes, add them to my family', style: TextStyle(color: careloopAccent, fontWeight: FontWeight.w700, fontSize: 13.5)),
                      const Text('Manage their bookings and health records from your account.', style: TextStyle(color: careloopAccent, fontSize: 11)),
                    ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.of(context).pop('guest'),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: careloopSurface, border: careloopCardBorder, borderRadius: BorderRadius.circular(16)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.circle_outlined, color: careloopMutedDim, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('No, just book a test', style: TextStyle(color: careloopTextPrimary, fontWeight: FontWeight.w700, fontSize: 13.5)),
                      Text('Book this test without adding them to your family.', style: TextStyle(color: careloopMuted, fontSize: 11)),
                    ]),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
