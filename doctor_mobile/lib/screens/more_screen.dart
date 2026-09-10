import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';
import 'home_shell.dart';
import 'notifications_screen.dart';
import 'practice_settings_screen.dart';
import 'billing_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final session = auth.session!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Text('More', style: docSectionHeading().copyWith(fontSize: 21)),
        const SizedBox(height: 16),
        DocCard(
          child: Row(children: [
            DoctorAvatar(name: session.displayName, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(session.displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                Text(session.role == 'provider_clinic_admin' ? 'Clinic admin' : 'Doctor', style: const TextStyle(fontSize: 11.5, color: docMuted)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        DocCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            _MenuRow(icon: Icons.notifications_rounded, label: 'Notifications', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()))),
            const Divider(height: 1),
            _MenuRow(icon: Icons.receipt_long_rounded, label: 'Billing', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BillingScreen()))),
            const Divider(height: 1),
            const _MenuRow(icon: Icons.description_rounded, label: 'Prescriptions', enabled: false),
            const Divider(height: 1),
            const _MenuRow(icon: Icons.science_rounded, label: 'Lab Orders', enabled: false),
            const Divider(height: 1),
            const _MenuRow(icon: Icons.folder_rounded, label: 'Documents', enabled: false),
            const Divider(height: 1),
            const _MenuRow(icon: Icons.bar_chart_rounded, label: 'Reports & Analytics', enabled: false),
            const Divider(height: 1),
            const _MenuRow(icon: Icons.local_hospital_rounded, label: 'Clinic', enabled: false),
            const Divider(height: 1),
            _MenuRow(icon: Icons.settings_rounded, label: 'Practice Settings', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PracticeSettingsScreen()))),
          ]),
        ),
        const SizedBox(height: 16),
        DocCard(
          child: InkWell(
            onTap: () => auth.logout(),
            child: const Row(children: [
              Icon(Icons.logout_rounded, color: docDanger, size: 18),
              SizedBox(width: 10),
              Text('Log out', style: TextStyle(color: docDanger, fontWeight: FontWeight.w700, fontSize: 13.5)),
            ]),
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;
  const _MenuRow({required this.icon, required this.label, this.enabled = true, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: docSurfaceRaised, borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 16, color: enabled ? docPrimary : docMutedDim),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: enabled ? docTextPrimary : docMutedDim))),
          if (!enabled) const Text('Coming soon', style: TextStyle(fontSize: 10.5, color: docMutedDim, fontWeight: FontWeight.w600))
          else const Icon(Icons.chevron_right_rounded, size: 16, color: docMutedDim),
        ]),
      ),
    );
  }
}
