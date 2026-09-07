import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../auth_provider.dart';
import '../../theme.dart';
import 'step_dots.dart';

String _formatTimeSlot(String slot) {
  final parts = slot.split('-');
  if (parts.length != 2) return slot;
  String fmt(String hhmm) {
    final p = hhmm.split(':');
    var h = int.tryParse(p[0]) ?? 0;
    final suffix = h >= 12 ? 'PM' : 'AM';
    h = h % 12;
    if (h == 0) h = 12;
    return '$h:${p[1]} $suffix';
  }

  return '${fmt(parts[0])} – ${fmt(parts[1])}';
}

/// Step 4 of 4: selecting several people doesn't create one shared booking — each person needs
/// their own sample collected, so this creates one booking PER PERSON and says so explicitly,
/// rather than implying a single combined order.
class LabTestConfirmScreen extends StatefulWidget {
  final List<Map<String, dynamic>> selectedTests;
  final String bookedDate;
  final String timeSlot;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> guests;
  const LabTestConfirmScreen({
    super.key,
    required this.selectedTests,
    required this.bookedDate,
    required this.timeSlot,
    required this.members,
    required this.guests,
  });

  @override
  State<LabTestConfirmScreen> createState() => _LabTestConfirmScreenState();
}

class _LabTestConfirmScreenState extends State<LabTestConfirmScreen> {
  bool _busy = false;

  double get _perPersonTotal => widget.selectedTests.fold<double>(0, (sum, t) => sum + (t['price'] as num).toDouble());
  int get _peopleCount => widget.members.length + widget.guests.length;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    final api = context.read<AuthProvider>().api;
    final testNames = widget.selectedTests.map((t) => t['name'] as String).toList();
    try {
      for (final m in widget.members) {
        await api.addLabTestBooking({
          'member_id': m['id'],
          'test_names': testNames,
          'booked_date': widget.bookedDate,
          'time_slot': widget.timeSlot,
        });
      }
      for (final g in widget.guests) {
        await api.addLabTestBooking({
          ...g,
          'test_names': testNames,
          'booked_date': widget.bookedDate,
          'time_slot': widget.timeSlot,
        });
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(_peopleCount == 1 ? 'Booking confirmed' : '$_peopleCount bookings confirmed'),
          content: const Text('Sample collection is scheduled for your chosen date and time. Track status from each member\'s Lab Tests tab.'),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final grandTotal = _perPersonTotal * _peopleCount;

    return Scaffold(
      backgroundColor: careloopBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(children: [
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(width: 34, height: 34, decoration: BoxDecoration(color: careloopSurface, shape: BoxShape.circle, border: careloopCardBorder), child: const Icon(Icons.arrow_back_ios_new_rounded, size: 15)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Confirm booking', style: careloopSectionHeading().copyWith(fontSize: 17)),
                      const SizedBox(height: 6),
                      const LabTestStepDots(step: 4),
                    ],
                  ),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SummaryRow(icon: Icons.opacity_rounded, iconBg: careloopAbnormalBg, iconColor: careloopDanger, label: 'TESTS', value: widget.selectedTests.map((t) => t['name']).join('\n')),
                        const Divider(height: 22),
                        _SummaryRow(
                          icon: Icons.calendar_month_rounded,
                          iconBg: careloopAccentLight,
                          iconColor: careloopAccent,
                          label: 'COLLECTION',
                          value: '${widget.bookedDate} · ${_formatTimeSlot(widget.timeSlot)}',
                        ),
                        const Divider(height: 22),
                        const _SummaryRow(icon: Icons.science_rounded, iconBg: careloopTealBg, iconColor: careloopTeal, label: 'LAB', value: 'Metropolis Lab'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('$_peopleCount separate booking${_peopleCount == 1 ? '' : 's'} will be created', style: const TextStyle(color: careloopMutedDim, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                  const SizedBox(height: 10),
                  for (final m in widget.members) _PersonRow(name: m['name'] ?? '', testCount: widget.selectedTests.length, total: _perPersonTotal),
                  for (final g in widget.guests) _PersonRow(name: g['guest_name'] ?? '', testCount: widget.selectedTests.length, total: _perPersonTotal),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(color: careloopSurface, border: Border(top: BorderSide(color: careloopBorder))),
              child: Row(children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('₹${grandTotal.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const Text('total', style: TextStyle(color: careloopMuted, fontSize: 10.5)),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(child: ElevatedButton(onPressed: _busy ? null : _confirm, child: Text(_busy ? 'Booking…' : 'Confirm booking'))),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String value;
  const _SummaryRow({required this.icon, required this.iconBg, required this.iconColor, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 30, height: 30, decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 14, color: iconColor)),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: careloopMutedDim, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
          ],
        ),
      ),
    ]);
  }
}

class _PersonRow extends StatelessWidget {
  final String name;
  final int testCount;
  final double total;
  const _PersonRow({required this.name, required this.testCount, required this.total});

  String _initials(String n) {
    final parts = n.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: careloopSurfaceRaised, shape: BoxShape.circle), child: Center(child: Text(_initials(name), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: careloopTextPrimary)))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                Text('$testCount test${testCount == 1 ? '' : 's'} · ₹${total.toStringAsFixed(0)}', style: const TextStyle(color: careloopMuted, fontSize: 10.5)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
