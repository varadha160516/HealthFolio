import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import '../../../widgets/empty_state.dart';

/// Order history + delivery status. Status is member-advanced (see pharmacy_orders.status check)
/// since there's no real courier integration behind this — "Mark as delivered" is the honest
/// stand-in for a webhook that doesn't exist.
class PharmacyOrdersScreen extends StatefulWidget {
  final String memberId;
  const PharmacyOrdersScreen({super.key, required this.memberId});
  @override
  State<PharmacyOrdersScreen> createState() => _PharmacyOrdersScreenState();
}

class _PharmacyOrdersScreenState extends State<PharmacyOrdersScreen> {
  List<dynamic>? _orders;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final orders = await api.getPharmacyOrders(widget.memberId);
    if (mounted) setState(() => _orders = orders);
  }

  Future<void> _updateStatus(String id, String status) async {
    final api = context.read<AuthProvider>().api;
    await api.updatePharmacyOrder(id, status);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: careloopBg,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: const Text('My medicine orders')),
      body: SafeArea(
        child: _orders == null
            ? const Center(child: CircularProgressIndicator())
            : _orders!.isEmpty
                ? const Center(child: EmptyState(icon: Icons.local_shipping_outlined, message: 'No medicine orders yet.'))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _orders!.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _OrderCard(order: _orders![i] as Map<String, dynamic>, onUpdate: _updateStatus),
                    ),
                  ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final void Function(String id, String status) onUpdate;
  const _OrderCard({required this.order, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final items = (order['line_items'] as List).cast<Map<String, dynamic>>();
    final status = order['status'] as String;
    final eta = order['estimated_delivery_date'] != null ? DateTime.tryParse(order['estimated_delivery_date'] as String)?.toLocal() : null;
    final (bg, fg, label) = switch (status) {
      'delivered' => (careloopGreenBg, careloopGreen, 'Delivered'),
      'cancelled' => (careloopAbnormalBg, careloopDanger, 'Cancelled'),
      _ => (careloopWarningBg, careloopWarning, 'Placed'),
    };

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final it in items) Text(it['medicine_name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
            child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 10.5)),
          ),
        ]),
        if (eta != null) ...[
          const SizedBox(height: 4),
          Text('Estimated delivery: ${DateFormat('MMM d, yyyy').format(eta)}', style: const TextStyle(color: careloopMuted, fontSize: 11)),
        ],
        if (status == 'placed') ...[
          const SizedBox(height: 10),
          Row(children: [
            OutlinedButton(onPressed: () => onUpdate(order['id'] as String, 'delivered'), child: const Text('Mark as delivered')),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => onUpdate(order['id'] as String, 'cancelled'),
              style: OutlinedButton.styleFrom(foregroundColor: careloopDanger, side: const BorderSide(color: careloopDanger)),
              child: const Text('Cancel'),
            ),
          ]),
        ],
      ]),
    );
  }
}
