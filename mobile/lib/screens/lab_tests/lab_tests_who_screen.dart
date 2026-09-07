import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../auth_provider.dart';
import '../../theme.dart';
import '../../utils/motion.dart';
import '../../utils/text_case.dart';
import 'add_family_member_sheet.dart';
import 'add_someone_new_sheet.dart';
import 'guest_booking_sheet.dart';
import 'lab_test_confirm_screen.dart';
import 'step_dots.dart';

/// Step 3 of 4: multi-select — the same tests, at the same collection window, can be booked for
/// several family members (and/or guests) at once, per the reordered flow.
class LabTestsWhoScreen extends StatefulWidget {
  final List<Map<String, dynamic>> selectedTests;
  final String bookedDate;
  final String timeSlot;
  const LabTestsWhoScreen({super.key, required this.selectedTests, required this.bookedDate, required this.timeSlot});

  @override
  State<LabTestsWhoScreen> createState() => _LabTestsWhoScreenState();
}

class _LabTestsWhoScreenState extends State<LabTestsWhoScreen> {
  List<dynamic>? _members;
  final Set<String> _selectedMemberIds = {};
  final List<Map<String, dynamic>> _guests = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final family = await api.getFamily();
    if (mounted) setState(() => _members = family['members'] as List<dynamic>);
  }

  int _age(String? dob) {
    if (dob == null) return 0;
    final d = DateTime.tryParse(dob);
    if (d == null) return 0;
    return (DateTime.now().difference(d).inDays / 365.25).floor();
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  Future<void> _addNew() async {
    final choice = await showModalBottomSheet<String>(context: context, isScrollControlled: true, builder: (_) => const AddSomeoneNewSheet());
    if (choice == null || !mounted) return;
    if (choice == 'family') {
      final added = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => const AddFamilyMemberSheet());
      if (added == true) _load();
    } else {
      final guest = await showModalBottomSheet<Map<String, dynamic>>(context: context, isScrollControlled: true, builder: (_) => const GuestBookingSheet());
      if (guest != null && mounted) setState(() => _guests.add(guest));
    }
  }

  Future<void> _continue() async {
    final members = (_members ?? const []).cast<Map<String, dynamic>>().where((m) => _selectedMemberIds.contains(m['id'])).toList();
    final result = await Navigator.of(context).push(pushRoute(LabTestConfirmScreen(
      selectedTests: widget.selectedTests,
      bookedDate: widget.bookedDate,
      timeSlot: widget.timeSlot,
      members: members,
      guests: _guests,
    )));
    if (result == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    if (_members == null) return const Scaffold(backgroundColor: careloopBg, body: Center(child: CircularProgressIndicator()));
    final members = _members!.cast<Map<String, dynamic>>();
    const pastels = [careloopLavender, careloopPeriwinkle, careloopBlush, careloopCream, careloopLilac];
    final totalSelected = _selectedMemberIds.length + _guests.length;

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
                      Text("Who's it for?", style: careloopSectionHeading().copyWith(fontSize: 17)),
                      const SizedBox(height: 6),
                      const LabTestStepDots(step: 3),
                    ],
                  ),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                children: [
                  const Text('Select one or more family members — the same tests are booked for each. You can also add someone new.', style: TextStyle(color: careloopMuted, fontSize: 12)),
                  const SizedBox(height: 14),
                  for (final (i, m) in members.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(careloopRadiusMd),
                        onTap: () => setState(() => _selectedMemberIds.contains(m['id']) ? _selectedMemberIds.remove(m['id']) : _selectedMemberIds.add(m['id'])),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: careloopSurface,
                            borderRadius: BorderRadius.circular(careloopRadiusMd),
                            border: Border.all(color: _selectedMemberIds.contains(m['id']) ? careloopPrimary : careloopBorder, width: _selectedMemberIds.contains(m['id']) ? 2 : 1),
                            boxShadow: careloopCardShadow,
                          ),
                          child: Row(children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(color: pastels[i % pastels.length].withValues(alpha: 0.9), shape: BoxShape.circle),
                              child: Center(child: Text(_initials(m['name'] ?? '?'), style: const TextStyle(color: careloopTextPrimary, fontWeight: FontWeight.w600, fontSize: 17))),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                                  Text(
                                    [
                                      m['relationship_to_primary'] == 'self' ? 'You' : capitalizeFirstOrNull((m['relationship_to_primary'] as String?)?.replaceAll('_', ' ')),
                                      '${_age(m['dob'] as String?)} yrs',
                                      if ((m['blood_group'] as String?)?.isNotEmpty == true) m['blood_group'],
                                    ].where((v) => v != null && v.toString().isNotEmpty).join(' · '),
                                    style: const TextStyle(color: careloopMuted, fontSize: 11.5),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: _selectedMemberIds.contains(m['id']) ? careloopPrimary : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                border: _selectedMemberIds.contains(m['id']) ? null : Border.all(color: careloopMutedDim, width: 1.5),
                              ),
                              child: _selectedMemberIds.contains(m['id']) ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null,
                            ),
                          ]),
                        ),
                      ),
                    ),
                  for (final g in _guests)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: Border.all(color: careloopPrimary, width: 2), boxShadow: careloopCardShadow),
                        child: Row(children: [
                          Container(width: 52, height: 52, decoration: BoxDecoration(color: careloopSurfaceRaised, shape: BoxShape.circle), child: Center(child: Text(_initials(g['guest_name'] ?? '?'), style: const TextStyle(color: careloopTextPrimary, fontWeight: FontWeight.w600, fontSize: 17)))),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(g['guest_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                                const Text('Guest · not a family member', style: TextStyle(color: careloopMuted, fontSize: 11.5)),
                              ],
                            ),
                          ),
                          IconButton(icon: const Icon(Icons.close_rounded, size: 18, color: careloopMutedDim), onPressed: () => setState(() => _guests.remove(g))),
                        ]),
                      ),
                    ),
                  InkWell(
                    borderRadius: BorderRadius.circular(careloopRadiusMd),
                    onTap: _addNew,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(careloopRadiusMd), border: Border.all(color: careloopMutedDim, width: 1.5)),
                      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_rounded, size: 16, color: careloopAccent),
                        SizedBox(width: 8),
                        Text('Add a new family member', style: TextStyle(color: careloopAccent, fontWeight: FontWeight.w700, fontSize: 13)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(color: careloopSurface, border: Border(top: BorderSide(color: careloopBorder))),
              child: ElevatedButton(
                onPressed: totalSelected == 0 ? null : () => _continue(),
                child: Text(totalSelected == 0 ? 'Select at least one person' : 'Continue — $totalSelected ${totalSelected == 1 ? 'person' : 'people'} selected'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
