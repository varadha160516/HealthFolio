import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../auth_provider.dart';
import '../../theme.dart';
import '../../utils/motion.dart';
import 'lab_test_datetime_screen.dart';
import 'step_dots.dart';

/// Step 1 of 4: real catalog (GET /lab-tests/catalog — a small fixed list, no lab-partner
/// integration exists). Tests now come before picking who it's for, per the reordered flow.
class ChooseTestsScreen extends StatefulWidget {
  const ChooseTestsScreen({super.key});

  @override
  State<ChooseTestsScreen> createState() => _ChooseTestsScreenState();
}

class _ChooseTestsScreenState extends State<ChooseTestsScreen> {
  List<dynamic>? _catalog;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final catalog = await api.getLabTestCatalog();
    if (mounted) setState(() => _catalog = catalog);
  }

  Future<void> _continue() async {
    final tests = _catalog!.cast<Map<String, dynamic>>().where((t) => _selected.contains(t['name'])).toList();
    final result = await Navigator.of(context).push(pushRoute(LabTestDateTimeScreen(selectedTests: tests)));
    // A confirmed booking pops `true` all the way back through every step in the flow — cascade
    // it so Home (at the bottom of the stack) is the one that ends up with the result.
    if (result == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    if (_catalog == null) return const Scaffold(backgroundColor: careloopBg, body: Center(child: CircularProgressIndicator()));
    final tests = _catalog!.cast<Map<String, dynamic>>();
    final total = tests.where((t) => _selected.contains(t['name'])).fold<double>(0, (sum, t) => sum + (t['price'] as num).toDouble());

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
                      Text('Choose lab tests', style: careloopSectionHeading().copyWith(fontSize: 17)),
                      const SizedBox(height: 6),
                      const LabTestStepDots(step: 1),
                    ],
                  ),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                children: [
                  const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('POPULAR TESTS', style: TextStyle(color: careloopMutedDim, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6))),
                  for (final t in tests) _TestRow(test: t, selected: _selected.contains(t['name']), onToggle: () => setState(() => _selected.contains(t['name']) ? _selected.remove(t['name']) : _selected.add(t['name']))),
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
                    Text('${_selected.length} test${_selected.length == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    Text('₹${total.toStringAsFixed(0)}', style: const TextStyle(color: careloopMuted, fontSize: 11)),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(child: ElevatedButton(onPressed: _selected.isEmpty ? null : () => _continue(), child: const Text('Continue → Date & time'))),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestRow extends StatelessWidget {
  final Map<String, dynamic> test;
  final bool selected;
  final VoidCallback onToggle;
  const _TestRow({required this.test, required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(careloopRadiusMd),
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: careloopSurface,
            borderRadius: BorderRadius.circular(careloopRadiusMd),
            border: Border.all(color: selected ? careloopPrimary : careloopBorder, width: selected ? 2 : 1),
            boxShadow: careloopCardShadow,
          ),
          child: Row(children: [
            Container(width: 34, height: 34, decoration: BoxDecoration(color: careloopAbnormalBg, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.opacity_rounded, size: 16, color: careloopDanger)),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(test['name'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  Text('${test['turnaround_label']} · ₹${(test['price'] as num).toStringAsFixed(0)}', style: const TextStyle(color: careloopMuted, fontSize: 10.5)),
                ],
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: selected ? careloopPrimary : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: selected ? null : Border.all(color: careloopBorder, width: 1.5),
              ),
              child: selected ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null,
            ),
          ]),
        ),
      ),
    );
  }
}
