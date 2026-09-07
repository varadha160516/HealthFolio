import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tabs/profile_tab.dart';
import 'tabs/overview_tab.dart';
import 'tabs/vitals_tab.dart';
import 'tabs/trends_tab.dart';
import 'tabs/health_analysis_tab.dart';
import 'tabs/documents_tab.dart';
import 'tabs/add_document_sheet.dart';
import 'tabs/medications_tab.dart';
import 'tabs/lab_tests_tab.dart';
import 'tabs/symptoms_tab.dart';
import 'ai_chat_screen.dart';
import 'audit_log_screen.dart';
import '../../theme.dart';
import '../../utils/motion.dart';
import '../../utils/text_case.dart';
import '../../widgets/glass.dart';
import '../../widgets/gradient_fab.dart';

// Each section carries its own category color (icon badge bg, icon/label fg) per the reference —
// the nav no longer uses one shared selected-state color for every item.
// Health Timeline and Upload are deliberately not in this list — hidden from the nav per request,
// not deleted: HealthTimelineTab/UploadTab still exist and still work, they're just unreachable
// from here now. Upload's capability (adding a document) is still reachable via the Documents
// tab's own "Add Document" flow.
const _kSections = <(String, IconData, Color, Color)>[
  ('Profile', Icons.person_rounded, careloopAccentLight, careloopAccent),
  ('Overview', Icons.grid_view_rounded, careloopAccentLight, careloopAccent),
  ('Vitals', Icons.favorite_rounded, careloopBlush, careloopDanger),
  ('Trends', Icons.trending_up_rounded, careloopPeriwinkle, careloopInfo),
  ('Health Analysis', Icons.pie_chart_rounded, careloopLavender, careloopSuccess),
  ('Symptoms', Icons.sentiment_satisfied_rounded, careloopOrangeBg, careloopOrange),
  ('Documents', Icons.folder_rounded, careloopAccentLight, careloopAccent),
  ('Medications', Icons.medication_rounded, careloopAbnormalBg, careloopDanger),
  ('Lab Tests', Icons.science_rounded, careloopTealBg, careloopTeal),
];

final _kDocumentsIndex = _kSections.length - 3;

/// Left-panel navigation + right-panel detail (per the Liquid Glass brief), replacing the
/// previous horizontal TabBar. Each section's content is only built the first time it's
/// selected — and, once built, stays alive underneath the others via IndexedStack — so opening
/// this screen doesn't fire all nine tabs' API calls at once, just the first (Profile).
class MemberProfileScreen extends StatefulWidget {
  final Map<String, dynamic> member;
  const MemberProfileScreen({super.key, required this.member});

  @override
  State<MemberProfileScreen> createState() => _MemberProfileScreenState();
}

const _kNavSidePrefKey = 'profile_nav_on_right';

class _MemberProfileScreenState extends State<MemberProfileScreen> {
  int _selected = 0;
  int _refreshKey = 0;
  // Collapsed by default — the panel only opens when the user explicitly taps the toggle chevron.
  bool _navExpanded = false;
  bool _navOnRight = false;
  late List<Widget> _slots;
  // One ScrollController per section, reused across rebuilds (see _select) — lets a tab keep its
  // fetched data cached in _slots while still resetting its own scroll position independently.
  final Map<int, ScrollController> _scrollControllers = {};

  @override
  void initState() {
    super.initState();
    _slots = List.generate(_kSections.length, (_) => const SizedBox.shrink());
    _slots[0] = _buildTab(0);
    _loadNavSide();
  }

  @override
  void dispose() {
    for (final c in _scrollControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadNavSide() async {
    final prefs = await SharedPreferences.getInstance();
    final onRight = prefs.getBool(_kNavSidePrefKey);
    if (mounted && onRight != null) setState(() => _navOnRight = onRight);
  }

  Future<void> _toggleNavSide() async {
    setState(() => _navOnRight = !_navOnRight);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNavSidePrefKey, _navOnRight);
  }

  void _bump() {
    setState(() {
      _refreshKey++;
      _slots = List.generate(_kSections.length, (_) => const SizedBox.shrink());
      _slots[_selected] = _buildTab(_selected);
    });
  }

  void _select(int i) {
    if (i == _selected) return;
    // The tab being switched away from should default back to the top the next time it's shown —
    // its fetched data stays cached in _slots, only the scroll offset resets.
    final leaving = _scrollControllers[_selected];
    if (leaving != null && leaving.hasClients) leaving.jumpTo(0);
    setState(() {
      _selected = i;
      if (_slots[i] is SizedBox) _slots[i] = _buildTab(i);
    });
  }

  Widget _buildTab(int i) {
    final controller = _scrollControllers.putIfAbsent(i, () => ScrollController());
    return PrimaryScrollController(controller: controller, child: _buildTabContent(i));
  }

  Widget _buildTabContent(int i) {
    final memberId = widget.member['id'] as String;
    switch (i) {
      case 0:
        return ProfileTab(key: ValueKey('profile-$_refreshKey'), memberId: memberId);
      case 1:
        return OverviewTab(key: ValueKey('overview-$_refreshKey'), memberId: memberId);
      case 2:
        return VitalsTab(key: ValueKey('vitals-$_refreshKey'), memberId: memberId);
      case 3:
        return TrendsTab(key: ValueKey('trends-$_refreshKey'), memberId: memberId);
      case 4:
        return HealthAnalysisTab(key: ValueKey('healthanalysis-$_refreshKey'), memberId: memberId);
      case 5:
        return SymptomsTab(key: ValueKey('symptoms-$_refreshKey'), memberId: memberId);
      case 6:
        return DocumentsTab(key: ValueKey('docs-$_refreshKey'), memberId: memberId);
      case 7:
        return MedicationsTab(key: ValueKey('meds-$_refreshKey'), memberId: memberId);
      default:
        return LabTestsTab(key: ValueKey('labtests-$_refreshKey'), memberId: memberId);
    }
  }

  int? _age(String? dob) {
    if (dob == null) return null;
    final d = DateTime.tryParse(dob);
    if (d == null) return null;
    return (DateTime.now().difference(d).inDays / 365.25).floor();
  }

  @override
  Widget build(BuildContext context) {
    final memberId = widget.member['id'] as String;
    final name = widget.member['name'] as String? ?? '';
    final relationship = capitalizeFirst((widget.member['relationship_to_primary'] as String? ?? '').replaceAll('_', ' '));
    final age = _age(widget.member['dob'] as String?);
    final subtitle = [if (relationship.isNotEmpty) relationship, if (age != null) '$age yrs'].join(' · ');

    return GlassScaffold(
      appBar: GlassAppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(color: careloopTextPrimary, fontWeight: FontWeight.w700, fontSize: 18)),
            if (subtitle.isNotEmpty) Text(subtitle, style: const TextStyle(color: careloopPanelLabel, fontWeight: FontWeight.w500, fontSize: 12)),
          ],
        ),
        actions: [
          // Per-user, persisted (SharedPreferences) — moves the nav panel to whichever side the
          // member prefers, rather than a fixed left-only layout.
          IconButton(
            tooltip: _navOnRight ? 'Move panel to the left' : 'Move panel to the right',
            icon: Icon(_navOnRight ? Icons.flip_to_front_rounded : Icons.flip_to_back_rounded),
            onPressed: _toggleNavSide,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (choice) {
              if (choice == 'audit_log') {
                Navigator.of(context).push(pushRoute(AuditLogScreen(memberId: memberId)));
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'audit_log', child: Text('Audit Log'))],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_navOnRight) ...[
                Expanded(
                  child: GlassPanel(
                    padding: const EdgeInsets.all(4),
                    child: IndexedStack(index: _selected, children: _slots),
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  width: _navExpanded ? 104 : 46,
                  child: _LeftNav(
                    selected: _selected,
                    expanded: _navExpanded,
                    onSelect: _select,
                    onToggle: () => setState(() => _navExpanded = !_navExpanded),
                    toggleIcon: _navExpanded ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
                  ),
                ),
              ] else ...[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  width: _navExpanded ? 104 : 46,
                  child: _LeftNav(
                    selected: _selected,
                    expanded: _navExpanded,
                    onSelect: _select,
                    onToggle: () => setState(() => _navExpanded = !_navExpanded),
                    toggleIcon: _navExpanded ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GlassPanel(
                    padding: const EdgeInsets.all(4),
                    child: IndexedStack(index: _selected, children: _slots),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      // "Ask me" lives here, not as a section — a floating button reachable from every section
      // above rather than requiring a switch first. Extended (icon + visible label) so the name
      // actually reads on screen, not just on long-press. On the Documents tab specifically, this
      // slot is taken over by "Add Document" instead — the Scaffold only has one FAB slot, and the
      // Documents tab's own primary action needs it more than chat does while you're there.
      floatingActionButton: _selected == _kDocumentsIndex
          ? GradientFab(
              tooltip: 'Add a document',
              label: 'Add Document',
              icon: Icons.add_rounded,
              onPressed: () async {
                final uploaded = await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => AddDocumentSheet(memberId: memberId),
                );
                if (uploaded == true) _bump();
              },
            )
          : GradientFab(
              tooltip: 'Ask me about ${widget.member['name'] ?? 'their health'}',
              label: 'Ask me',
              icon: Icons.chat_bubble_rounded,
              onPressed: () => Navigator.push(context, pushRoute(AiChatScreen(member: widget.member))),
            ),
      fabStorageKey: 'profile_ask_me',
    );
  }
}

/// The nav rail — icon+label ROWS (not icon-over-label columns), collapsible so the right-detail
/// panel can claim more width when the nav isn't needed. Each item's icon badge always carries its
/// own category color; the selected item additionally gets a light background tint in that same
/// color and its label switches to the matching color, bold. Unselected items stay a muted gray
/// label over their (still colored) icon badge.
class _LeftNav extends StatelessWidget {
  final int selected;
  final bool expanded;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggle;
  final IconData toggleIcon;
  const _LeftNav({required this.selected, required this.expanded, required this.onSelect, required this.onToggle, required this.toggleIcon});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Column(
        children: [
          // Always visible, in both states, so the nav is never stuck collapsed with no way back.
          InkWell(
            borderRadius: BorderRadius.circular(careloopRadiusSm),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Icon(toggleIcon, size: 20, color: careloopPanelLabel),
            ),
          ),
          const Divider(height: 12, color: careloopPanelBorder),
          Expanded(
            child: ListView.separated(
              itemCount: _kSections.length,
              separatorBuilder: (context, i) => const SizedBox(height: 2),
              itemBuilder: (context, i) {
                final (label, icon, badgeBg, fg) = _kSections[i];
                final isSelected = i == selected;
                final badge = Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(9)),
                  child: Icon(icon, size: 14, color: fg),
                );
                return Tooltip(
                  message: expanded ? '' : label,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(careloopRadiusSm),
                    onTap: () => onSelect(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 5),
                      decoration: BoxDecoration(
                        color: isSelected ? badgeBg.withValues(alpha: 0.55) : Colors.transparent,
                        borderRadius: BorderRadius.circular(careloopRadiusSm),
                      ),
                      child: expanded
                          ? Row(children: [
                              badge,
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  label,
                                  maxLines: 2,
                                  style: TextStyle(fontSize: 11, height: 1.15, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500, color: isSelected ? fg : careloopPanelLabel),
                                ),
                              ),
                            ])
                          : Center(child: badge),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
