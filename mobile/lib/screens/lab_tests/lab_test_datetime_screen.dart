import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../utils/motion.dart';
import 'lab_tests_who_screen.dart';
import 'step_dots.dart';

const _kTimeSlots = <(String, String, String)>[
  ('07:00-09:00', '7:00 – 9:00 AM', 'Early morning'),
  ('09:00-11:00', '9:00 – 11:00 AM', 'Morning'),
  ('16:00-18:00', '4:00 – 6:00 PM', 'Evening'),
];

/// Step 2 of 4: a real collection-window picker — the app previously skipped this and silently
/// booked against "next available". Still illustrative (no real phlebotomist-availability
/// backend), but now a real interaction the member drives instead of one assumed away.
class LabTestDateTimeScreen extends StatefulWidget {
  final List<Map<String, dynamic>> selectedTests;
  const LabTestDateTimeScreen({super.key, required this.selectedTests});

  @override
  State<LabTestDateTimeScreen> createState() => _LabTestDateTimeScreenState();
}

class _LabTestDateTimeScreenState extends State<LabTestDateTimeScreen> {
  late final List<DateTime> _dates;
  late DateTime _selectedDate;
  String _selectedSlot = _kTimeSlots.first.$1;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _dates = List.generate(7, (i) => DateTime(today.year, today.month, today.day + i));
    _selectedDate = _dates[1]; // tomorrow, matching "next available" default
  }

  Future<void> _continue() async {
    final result = await Navigator.of(context).push(pushRoute(LabTestsWhoScreen(
      selectedTests: widget.selectedTests,
      bookedDate: _selectedDate.toIso8601String().substring(0, 10),
      timeSlot: _selectedSlot,
    )));
    if (result == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final testNames = widget.selectedTests.map((t) => t['name']).join(', ');

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
                      Text('Choose date & time', style: careloopSectionHeading().copyWith(fontSize: 17)),
                      const SizedBox(height: 6),
                      const LabTestStepDots(step: 2),
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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${widget.selectedTests.length} test${widget.selectedTests.length == 1 ? '' : 's'} selected', style: const TextStyle(color: careloopMutedDim, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                        const SizedBox(height: 3),
                        Text(testNames, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('COLLECTION DATE', style: TextStyle(color: careloopMutedDim, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 66,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _dates.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final d = _dates[i];
                        final selected = d.year == _selectedDate.year && d.month == _selectedDate.month && d.day == _selectedDate.day;
                        final isToday = i == 0;
                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => setState(() => _selectedDate = d),
                          child: Container(
                            width: 52,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: selected ? careloopPrimary : (isToday ? careloopSurfaceRaised : careloopSurface),
                              borderRadius: BorderRadius.circular(16),
                              border: selected || isToday ? null : careloopCardBorder,
                            ),
                            child: Column(children: [
                              Text(isToday ? 'TODAY' : weekdays[d.weekday - 1], style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: selected ? Colors.white.withValues(alpha: 0.85) : careloopMuted)),
                              const SizedBox(height: 2),
                              Text('${d.day}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: selected ? Colors.white : careloopTextPrimary)),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('COLLECTION TIME', style: TextStyle(color: careloopMutedDim, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                  const SizedBox(height: 10),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.9,
                    children: [for (final s in _kTimeSlots) _SlotTile(value: s.$1, label: s.$2, sub: s.$3, selected: _selectedSlot == s.$1, onTap: () => setState(() => _selectedSlot = s.$1))],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: careloopAccentLight, borderRadius: BorderRadius.circular(careloopRadiusMd)),
                    child: const Row(children: [
                      Icon(Icons.home_rounded, size: 16, color: careloopAccent),
                      SizedBox(width: 8),
                      Expanded(child: Text('A phlebotomist collects the sample at your home address on file.', style: TextStyle(fontSize: 10.5, color: careloopAccent, fontWeight: FontWeight.w500))),
                    ]),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(color: careloopSurface, border: Border(top: BorderSide(color: careloopBorder))),
              child: ElevatedButton(onPressed: () => _continue(), child: const Text("Continue → Who's it for")),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  final String value;
  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;
  const _SlotTile({required this.value, required this.label, required this.sub, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(color: selected ? careloopPrimary : careloopSurface, borderRadius: BorderRadius.circular(14), border: selected ? null : careloopCardBorder),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.schedule_rounded, size: 15, color: selected ? Colors.white : careloopTextPrimary),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : careloopTextPrimary)),
          Text(sub, style: TextStyle(fontSize: 9.5, color: selected ? Colors.white.withValues(alpha: 0.85) : careloopMuted)),
        ]),
      ),
    );
  }
}
