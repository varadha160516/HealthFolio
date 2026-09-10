import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';

/// This doctor's own audit trail — the same audit_log table the member's "Consent & access log"
/// already reads, filtered to entries this account actually performed. Read-only.
class ComplianceScreen extends StatefulWidget {
  const ComplianceScreen({super.key});
  @override
  State<ComplianceScreen> createState() => _ComplianceScreenState();
}

class _ComplianceScreenState extends State<ComplianceScreen> {
  List<dynamic>? _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await context.read<AuthProvider>().api.getMyAuditLog();
    if (mounted) setState(() => _entries = entries);
  }

  String _actionLabel(String action) => action.replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    return DocGradientScaffold(
      appBar: AppBar(title: const Text('Compliance')),
      body: _entries == null
          ? const LoadingCenter()
          : _entries!.isEmpty
              ? const Center(child: EmptyState(icon: Icons.verified_user_outlined, message: 'No audit entries yet.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: _entries!.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final e = _entries![i] as Map<String, dynamic>;
                      final ts = DateTime.tryParse(e['timestamp'] as String? ?? '')?.toLocal();
                      return DocCard(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(color: docSurfaceRaised, borderRadius: BorderRadius.circular(9)),
                            child: const Icon(Icons.history_rounded, size: 15, color: docMuted),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(_actionLabel(e['action'] as String? ?? ''), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                              if (ts != null) Text(DateFormat('MMM d, yyyy · h:mm a').format(ts), style: const TextStyle(fontSize: 11, color: docMuted)),
                            ]),
                          ),
                        ]),
                      );
                    },
                  ),
                ),
    );
  }
}
