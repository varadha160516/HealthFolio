import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/section_card.dart';
import '../referral_booking_screen.dart';

/// Referrals a doctor has made for this member — real clinical context (reason + notes) carried
/// forward to whichever specialist the family books with, rather than a slip of paper. See
/// server/src/pipeline/previsitPrep.ts for how that context reaches the receiving doctor.
class ReferralsTab extends StatefulWidget {
  final String memberId;
  const ReferralsTab({super.key, required this.memberId});
  @override
  State<ReferralsTab> createState() => _ReferralsTabState();
}

class _ReferralsTabState extends State<ReferralsTab> {
  List<dynamic>? _referrals;
  bool _showHistory = false;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final referrals = await api.getMemberReferrals(widget.memberId);
    if (mounted) setState(() => _referrals = referrals);
  }

  Future<void> _book(Map<String, dynamic> referral) async {
    final booked = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ReferralBookingScreen(referral: referral, memberId: widget.memberId)),
    );
    if (booked == true) _load();
  }

  Future<void> _cancel(Map<String, dynamic> referral) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Decline this referral?'),
        content: const Text("You won't be prompted to book this specialist visit again."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: careloopDanger), onPressed: () => Navigator.pop(context, true), child: const Text('Decline')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy.add(referral['id'] as String));
    try {
      final api = context.read<AuthProvider>().api;
      await api.cancelReferral(referral['id'] as String);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy.remove(referral['id']));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_referrals == null) return const LoadingCenter();
    final all = _referrals!.cast<Map<String, dynamic>>();
    final pending = all.where((r) => r['status'] == 'pending').toList();
    final history = all.where((r) => r['status'] != 'pending').toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, careloopFabClearance),
        children: [
          Text('Referrals', style: careloopPageTitle().copyWith(fontSize: 21)),
          const SizedBox(height: 2),
          const Text('Specialist referrals from your doctors, with their notes carried forward automatically.', style: TextStyle(color: careloopMuted, fontSize: 11.5)),
          const SizedBox(height: 14),
          if (pending.isEmpty && history.isEmpty)
            const EmptyState(icon: Icons.forward_to_inbox_rounded, message: 'No referrals yet.')
          else if (pending.isEmpty)
            const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('No pending referrals to act on.', style: TextStyle(color: careloopMuted, fontSize: 12.5))),
          for (final r in pending) _ReferralCard(referral: r, busy: _busy.contains(r['id']), onBook: () => _book(r), onCancel: () => _cancel(r)),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () => setState(() => _showHistory = !_showHistory),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Icon(_showHistory ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: careloopMuted),
                  const SizedBox(width: 4),
                  Text('${history.length} past referral${history.length == 1 ? '' : 's'}', style: const TextStyle(color: careloopMuted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            if (_showHistory) for (final r in history) _ReferralCard(referral: r, resolved: true),
          ],
        ],
      ),
    );
  }
}

class _ReferralCard extends StatelessWidget {
  final Map<String, dynamic> referral;
  final bool resolved;
  final bool busy;
  final VoidCallback? onBook;
  final VoidCallback? onCancel;
  const _ReferralCard({required this.referral, this.resolved = false, this.busy = false, this.onBook, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final target = referral['target_provider_name'] as String? ?? referral['target_specialty'] as String? ?? 'Specialist';
    final referringName = referral['referring_provider_name'] as String? ?? 'Your doctor';
    final createdAt = DateTime.tryParse(referral['created_at'] as String? ?? '')?.toLocal();
    final isUrgent = referral['urgency'] == 'urgent';
    final status = referral['status'] as String;
    final (statusBg, statusFg, statusLabel) = switch (status) {
      'booked' => (careloopNewBg, careloopInfo, 'Booked'),
      'completed' => (careloopGreenBg, careloopGreen, 'Completed'),
      'cancelled' => (careloopAbnormalBg, careloopDanger, 'Declined'),
      _ => (careloopWarningBg, careloopWarning, 'Pending'),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: resolved ? null : careloopCardShadow),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Referred to: $target', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              Text('by $referringName${createdAt != null ? ' · ${DateFormat('MMM d, yyyy').format(createdAt)}' : ''}', style: const TextStyle(color: careloopMuted, fontSize: 11)),
            ]),
          ),
          if (isUrgent && !resolved)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: careloopAbnormalBg, borderRadius: BorderRadius.circular(999)),
              child: const Text('Urgent', style: TextStyle(color: careloopDanger, fontWeight: FontWeight.w700, fontSize: 9.5)),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(999)),
            child: Text(statusLabel, style: TextStyle(color: statusFg, fontWeight: FontWeight.w700, fontSize: 10)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(referral['reason'] ?? '', style: const TextStyle(fontSize: 12, height: 1.4)),
        if (!resolved) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : onCancel,
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 9), minimumSize: Size.zero),
                child: const Text('Decline', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: busy ? null : onBook,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 9), minimumSize: Size.zero),
                child: const Text('Book appointment', style: TextStyle(fontSize: 12)),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}
