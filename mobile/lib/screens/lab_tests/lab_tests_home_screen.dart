import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../auth_provider.dart';
import '../../theme.dart';
import '../../utils/motion.dart';
import '../../widgets/section_card.dart';
import 'choose_tests_screen.dart';

/// The bottom-nav "Lab Tests" tab — a prominent "Book new test" entry into the 4-step flow
/// (Tests → Date & time → Who's it for → Confirm), plus a quick glance at the family's bookings.
class LabTestsHomeScreen extends StatefulWidget {
  const LabTestsHomeScreen({super.key});
  @override
  State<LabTestsHomeScreen> createState() => _LabTestsHomeScreenState();
}

class _LabTestsHomeScreenState extends State<LabTestsHomeScreen> {
  List<dynamic>? _bookings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final bookings = await api.getFamilyLabTestBookings();
    if (mounted) setState(() => _bookings = bookings);
  }

  Future<void> _bookNew() async {
    final result = await Navigator.of(context).push(pushRoute(const ChooseTestsScreen()));
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_bookings == null) return const LoadingCenter();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, careloopFabClearance),
        children: [
          Text('Lab Tests', style: careloopPageTitle().copyWith(fontSize: 21)),
          const SizedBox(height: 2),
          const Text('Manage lab test bookings for your family', style: TextStyle(color: careloopMuted, fontSize: 11.5)),
          const SizedBox(height: 16),
          InkWell(
            borderRadius: BorderRadius.circular(careloopRadiusMd),
            onTap: _bookNew,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: careloopPrimaryGradient), borderRadius: BorderRadius.circular(careloopRadiusMd)),
              child: Row(children: [
                Container(width: 42, height: 42, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle), child: const Icon(Icons.add_rounded, color: Colors.white, size: 22)),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Book new test', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                      Text('Choose tests, pick a time, then who it\'s for', style: TextStyle(color: Colors.white70, fontSize: 11.5)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white),
              ]),
            ),
          ),
          if (_bookings!.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text('Recent bookings', style: careloopSectionHeading().copyWith(fontSize: 15)),
            const SizedBox(height: 10),
            for (final b in _bookings!.cast<Map<String, dynamic>>()) _BookingRow(booking: b),
          ],
        ],
      ),
    );
  }
}

class _BookingRow extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _BookingRow({required this.booking});

  @override
  Widget build(BuildContext context) {
    final tests = (booking['test_names'] as List).cast<String>();
    final who = booking['guest_name'] ?? 'Family member';
    final status = booking['status'] as String;
    final (bg, fg, label) = switch (status) {
      'report_ready' => (careloopGreenBg, careloopGreen, 'Reports Delivered'),
      'processing' => (careloopNewBg, careloopInfo, 'Collection Done'),
      'cancelled' => (careloopAbnormalBg, careloopDanger, 'Cancelled'),
      _ => (careloopWarningBg, careloopWarning, 'Collection Scheduled'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final t in tests)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 4, height: 4, margin: const EdgeInsets.only(right: 6), decoration: const BoxDecoration(color: careloopTextPrimary, shape: BoxShape.circle)),
                      Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ]),
                  ),
                Text('$who · ${booking['lab_name']}', style: const TextStyle(color: careloopMuted, fontSize: 10.5)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
            child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 10)),
          ),
        ]),
      ),
    );
  }
}
