import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../auth_provider.dart';
import '../../theme.dart';
import 'admin_applications_screen.dart';

/// The platform_admin's own app shell — a single review queue, since provider onboarding is the
/// only admin workflow this app exposes a UI for (dictionary curation etc. stay API-only). Reuses
/// ClinDesk's login/session/theme rather than being a separate app.
class AdminShell extends StatelessWidget {
  const AdminShell({super.key});

  @override
  Widget build(BuildContext context) {
    return DocGradientScaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(gradient: const LinearGradient(colors: docPrimaryGradient), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 9),
          Text('ClinDesk Admin', style: docSectionHeading().copyWith(fontSize: 18)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.logout_rounded), tooltip: 'Log out', onPressed: () => context.read<AuthProvider>().logout()),
        ],
      ),
      body: const AdminApplicationsScreen(),
    );
  }
}
