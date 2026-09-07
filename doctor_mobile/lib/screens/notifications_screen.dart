import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<dynamic>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final items = await api.getNotifications();
    if (mounted) setState(() => _items = items);
  }

  (IconData, Color, Color) _style(String type) => switch (type) {
        'lab_report_ready' => (Icons.science_rounded, docTeal, docTealBg),
        'follow_up_due' => (Icons.event_repeat_rounded, docAccent, docAccentLight),
        'appointment_cancelled' => (Icons.event_busy_rounded, docDanger, docDangerBg),
        _ => (Icons.notifications_rounded, docMuted, docSurfaceRaised),
      };

  @override
  Widget build(BuildContext context) {
    if (_items == null) return const DocGradientScaffold(body: LoadingCenter());
    return DocGradientScaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _items!.isEmpty
            ? ListView(children: const [EmptyState(icon: Icons.notifications_off_rounded, message: 'No notifications yet.')])
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: _items!.length,
                itemBuilder: (context, i) {
                  final n = _items![i] as Map<String, dynamic>;
                  final (icon, fg, bg) = _style(n['type'] as String);
                  final read = n['read_at'] != null;
                  final dt = DateTime.tryParse(n['created_at'] as String? ?? '')?.toLocal();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Opacity(
                      opacity: read ? 0.65 : 1,
                      child: DocCard(
                        padding: const EdgeInsets.all(13),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(width: 38, height: 38, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)), child: Icon(icon, size: 18, color: fg)),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(n['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                              const SizedBox(height: 2),
                              Text(n['body'] ?? '', style: const TextStyle(fontSize: 12, color: docMuted)),
                              const SizedBox(height: 5),
                              Text(dt != null ? DateFormat('MMM d, h:mm a').format(dt) : '', style: const TextStyle(fontSize: 10.5, color: docMutedDim)),
                            ]),
                          ),
                          if (!read)
                            Container(width: 7, height: 7, margin: const EdgeInsets.only(top: 4), decoration: const BoxDecoration(color: docPrimary, shape: BoxShape.circle)),
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
