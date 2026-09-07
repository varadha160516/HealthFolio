import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme.dart';

class AppointmentCard extends StatelessWidget {
  final Map<String, dynamic> appt;
  final VoidCallback onTap;
  const AppointmentCard({super.key, required this.appt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final member = appt['member'] as Map<String, dynamic>?;
    final status = appt['status'] as String;
    final datetime = DateTime.tryParse(appt['datetime'] as String? ?? '')?.toLocal();
    final reason = appt['reason_for_visit'] as String?;
    final dob = member?['dob'] as String?;
    final age = dob != null ? (DateTime.now().difference(DateTime.tryParse(dob) ?? DateTime.now()).inDays / 365.25).floor() : null;
    final sex = (member?['sex'] as String?);
    final sexLabel = sex == null || sex.isEmpty ? '' : sex[0].toUpperCase();

    return InkWell(
      borderRadius: BorderRadius.circular(docRadiusMd),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: docSurface, borderRadius: BorderRadius.circular(docRadiusMd), border: docCardBorder, boxShadow: docCardShadow),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(datetime != null ? DateFormat('h:mm a').format(datetime) : '—', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: docAccent, letterSpacing: 0.2)),
            const Spacer(),
            StatusPill.forAppointment(status),
          ]),
          const SizedBox(height: 6),
          Text('${member?['name'] ?? 'Unknown patient'}${age != null ? ' · $age$sexLabel' : ''}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          if (reason != null && reason.isNotEmpty) ...[
            const SizedBox(height: 2),
            Row(children: [
              Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 6), decoration: const BoxDecoration(color: docAccent, shape: BoxShape.circle)),
              Expanded(child: Text(reason, style: const TextStyle(fontSize: 12.5, color: docMuted, fontWeight: FontWeight.w500))),
            ]),
          ],
        ]),
      ),
    );
  }
}
