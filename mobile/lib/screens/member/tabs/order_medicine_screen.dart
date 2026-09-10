import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';

/// Orders straight from the member's own active medication list — no separate pharmacy catalog.
/// Delivery is a demo timeline (see pharmacyOrders.ts): no real courier is wired up.
class OrderMedicineScreen extends StatefulWidget {
  final String memberId;
  final List<Map<String, dynamic>> activeMedications;
  const OrderMedicineScreen({super.key, required this.memberId, required this.activeMedications});

  @override
  State<OrderMedicineScreen> createState() => _OrderMedicineScreenState();
}

class _OrderMedicineScreenState extends State<OrderMedicineScreen> {
  late final Set<int> _selected = {for (var i = 0; i < widget.activeMedications.length; i++) i};
  final _address = TextEditingController();
  bool _placing = false;
  String? _error;

  Future<void> _place() async {
    if (_selected.isEmpty) {
      setState(() => _error = 'Select at least one medicine');
      return;
    }
    if (_address.text.trim().isEmpty) {
      setState(() => _error = 'Enter a delivery address');
      return;
    }
    setState(() {
      _placing = true;
      _error = null;
    });
    try {
      final lineItems = [
        for (final i in _selected)
          {
            'medicine_name': widget.activeMedications[i]['medicine_name'],
            'strength': widget.activeMedications[i]['strength'],
            'quantity': 1,
          },
      ];
      final api = context.read<AuthProvider>().api;
      await api.placePharmacyOrder(widget.memberId, {'line_items': lineItems, 'delivery_address': _address.text.trim()});
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: careloopBg,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: const Text('Order medicine')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Select medicines to order', style: TextStyle(fontSize: 12.5, color: careloopMuted)),
            const SizedBox(height: 10),
            Expanded(
              child: widget.activeMedications.isEmpty
                  ? const Center(child: Text('No active medications to order.', style: TextStyle(color: careloopMuted)))
                  : ListView.separated(
                      itemCount: widget.activeMedications.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final med = widget.activeMedications[i];
                        final checked = _selected.contains(i);
                        return InkWell(
                          borderRadius: BorderRadius.circular(careloopRadiusMd),
                          onTap: () => setState(() => checked ? _selected.remove(i) : _selected.add(i)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder),
                            child: Row(children: [
                              Checkbox(value: checked, onChanged: (v) => setState(() => v == true ? _selected.add(i) : _selected.remove(i))),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(med['medicine_name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                                  if ((med['strength'] as String? ?? '').isNotEmpty) Text(med['strength'], style: const TextStyle(color: careloopMuted, fontSize: 11.5)),
                                ]),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Delivery address'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: careloopDanger, fontSize: 12.5)),
            ],
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _placing ? null : _place,
              child: Text(_placing ? 'Placing order…' : 'Place order'),
            ),
          ]),
        ),
      ),
    );
  }
}
