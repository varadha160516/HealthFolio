import 'package:flutter/material.dart';
import 'tabs/consent_tab.dart';
import '../../widgets/glass.dart';

/// Formerly the "Consent & Privacy" tab — moved off the main tab bar and into each member's
/// 3-dot menu, since it's a check-occasionally screen rather than something used every visit.
/// Same data/functionality as before (consent requests + the access audit log), just relocated.
class AuditLogScreen extends StatelessWidget {
  final String memberId;
  const AuditLogScreen({super.key, required this.memberId});

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(title: const Text('Audit Log')),
      body: ConsentTab(memberId: memberId),
    );
  }
}
