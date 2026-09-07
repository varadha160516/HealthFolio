import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import '../../../widgets/ledger.dart';
import '../../../widgets/section_card.dart';

class ConsentTab extends StatefulWidget {
  final String memberId;
  const ConsentTab({super.key, required this.memberId});
  @override
  State<ConsentTab> createState() => _ConsentTabState();
}

class _ConsentTabState extends State<ConsentTab> {
  List<dynamic>? _appointments;
  List<dynamic>? _audit;
  final Map<String, String> _explanations = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final all = await api.getAppointments();
    final audit = await api.getAudit(widget.memberId);
    if (!mounted) return;
    final pending = all.where((a) => a['member']?['id'] == widget.memberId).toList();
    setState(() {
      _appointments = pending;
      _audit = audit;
    });
    _loadExplanations(pending.where((a) => a['status'] == 'consent_requested').toList());
  }

  /// Consent explainer agent (Roadmap Section 2.5) — fetched per pending request, once, and
  /// cached client-side for the life of this screen. Fails silently: falls back to the plain
  /// scope sentence below rather than blocking Approve/Deny on a model call.
  Future<void> _loadExplanations(List<dynamic> pending) async {
    final api = context.read<AuthProvider>().api;
    for (final a in pending) {
      final id = a['id'] as String;
      if (_explanations.containsKey(id)) continue;
      try {
        final r = await api.getConsentExplanation(id);
        if (mounted) setState(() => _explanations[id] = r['explanation'] as String);
      } catch (_) {
        // silent — see doc comment above
      }
    }
  }

  Future<void> _respond(String id, bool approve) async {
    await context.read<AuthProvider>().api.respondConsent(id, approve);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_appointments == null || _audit == null) return const LoadingCenter();
    final pending = _appointments!.where((a) => a['status'] == 'consent_requested').toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (pending.isNotEmpty)
            SectionCard(
              title: 'Consent requests waiting on you',
              child: Column(
                children: [
                  for (final a in pending)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InfoBanner(
                        _explanations[a['id']] ?? '${a['provider']?['name']} is requesting ${a['consentGrant']?['scope'] ?? 'full history'} access for today\'s visit.',
                      ),
                    ),
                  for (final a in pending)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        ElevatedButton(onPressed: () => _respond(a['id'], true), child: const Text('Approve')),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => _respond(a['id'], false),
                          style: OutlinedButton.styleFrom(foregroundColor: careloopDanger),
                          child: const Text('Deny'),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
          LedgerTable(
            title: 'Consent & access log',
            rows: _audit!.isEmpty
                ? [const LedgerRow(label: 'No provider or payer has accessed this record yet', trailing: SizedBox.shrink())]
                : [
                    for (final e in _audit!.cast<Map<String, dynamic>>())
                      LedgerRow(
                        label: (e['action'] as String).replaceAll('_', ' '),
                        sublabel: (e['actor_role'] as String).replaceAll('_', ' '),
                        trailing: Text((e['timestamp'] as String).substring(0, 16).replaceAll('T', ' '), style: careloopDataInline(size: careloopTypeCaption, color: careloopMuted)),
                      ),
                  ],
          ),
        ],
      ),
    );
  }
}
