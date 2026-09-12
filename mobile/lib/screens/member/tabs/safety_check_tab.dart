import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/section_card.dart';

/// Cross-provider safety net — structured-fact checks (duplicate active medications from
/// different prescribers, a medication name matching a recorded allergy, a lab test repeated
/// within weeks) run across this member's ENTIRE record, not just one doctor's own visit notes.
/// Deliberately member-facing only: no doctor sees this, and it never guesses at drug interactions
/// or diagnoses — only what's already a structured fact on file. See server/src/pipeline/safetyNet.ts.
class SafetyCheckTab extends StatefulWidget {
  final String memberId;
  const SafetyCheckTab({super.key, required this.memberId});
  @override
  State<SafetyCheckTab> createState() => _SafetyCheckTabState();
}

class _SafetyCheckTabState extends State<SafetyCheckTab> {
  Map<String, dynamic>? _result;
  bool _showHistory = false;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final result = await api.getSafetyFlags(widget.memberId);
    if (mounted) setState(() => _result = result);
  }

  Future<void> _act(String flagId, Future<void> Function(String) action) async {
    setState(() => _busy.add(flagId));
    try {
      await action.call(flagId);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy.remove(flagId));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_result == null) return const LoadingCenter();
    final open = (_result!['open'] as List).cast<Map<String, dynamic>>();
    final history = (_result!['history'] as List).cast<Map<String, dynamic>>();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, careloopFabClearance),
        children: [
          Text('Health Safety Check', style: careloopPageTitle().copyWith(fontSize: 21)),
          const SizedBox(height: 2),
          const Text('Checked across every doctor and lab test on file — not just one visit.', style: TextStyle(color: careloopMuted, fontSize: 11.5)),
          const SizedBox(height: 14),
          if (open.isEmpty)
            const EmptyState(icon: Icons.verified_user_rounded, message: 'Nothing to review right now.')
          else
            for (final f in open) _FlagCard(flag: f, busy: _busy.contains(f['id']), onDismiss: () => _act(f['id'] as String, context.read<AuthProvider>().api.dismissSafetyFlag), onDiscussed: () => _act(f['id'] as String, context.read<AuthProvider>().api.markSafetyFlagDiscussed)),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => setState(() => _showHistory = !_showHistory),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Icon(_showHistory ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: careloopMuted),
                  const SizedBox(width: 4),
                  Text('${history.length} previously reviewed', style: const TextStyle(color: careloopMuted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            if (_showHistory) for (final f in history) _FlagCard(flag: f, resolved: true),
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: careloopSurfaceRaised, borderRadius: BorderRadius.circular(careloopRadiusMd)),
            child: const Text(
              'These are automated checks against your own records — not medical advice and not a diagnosis. Always confirm with your doctor or pharmacist before changing anything.',
              style: TextStyle(color: careloopMuted, fontSize: 11, height: 1.4, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlagCard extends StatelessWidget {
  final Map<String, dynamic> flag;
  final bool resolved;
  final bool busy;
  final VoidCallback? onDismiss;
  final VoidCallback? onDiscussed;
  const _FlagCard({required this.flag, this.resolved = false, this.busy = false, this.onDismiss, this.onDiscussed});

  @override
  Widget build(BuildContext context) {
    final severity = flag['severity'] as String;
    final (bg, fg, icon) = switch (severity) {
      'warning' => (careloopWarningBg, careloopWarning, Icons.warning_amber_rounded),
      _ => (careloopNewBg, careloopInfo, Icons.info_outline_rounded),
    };
    final createdAt = DateTime.tryParse(flag['created_at'] as String? ?? '')?.toLocal();

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: resolved ? careloopSurface : bg,
        borderRadius: BorderRadius.circular(careloopRadiusMd),
        border: resolved ? careloopCardBorder : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: resolved ? careloopMuted : fg),
          const SizedBox(width: 9),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(flag['title'] ?? '', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: resolved ? careloopTextPrimary : fg)),
              const SizedBox(height: 4),
              Text(flag['detail'] ?? '', style: TextStyle(fontSize: 11.5, height: 1.4, color: resolved ? careloopMuted : fg.withValues(alpha: 0.9))),
              if (createdAt != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(DateFormat('MMM d, yyyy').format(createdAt), style: const TextStyle(color: careloopMutedDim, fontSize: 10))),
            ]),
          ),
        ]),
        if (resolved) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: careloopSurfaceRaised, borderRadius: BorderRadius.circular(999)),
            child: Text(flag['status'] == 'discussed' ? 'Discussed with doctor' : 'Dismissed', style: const TextStyle(color: careloopMuted, fontSize: 10, fontWeight: FontWeight.w600)),
          ),
        ] else ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : onDismiss,
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 9), minimumSize: Size.zero),
                child: const Text('Dismiss', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: busy ? null : onDiscussed,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 9), minimumSize: Size.zero),
                child: busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Discussed with doctor', style: TextStyle(fontSize: 12)),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}
