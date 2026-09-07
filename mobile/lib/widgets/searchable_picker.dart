import 'package:flutter/material.dart';
import '../theme.dart';

/// A full-height searchable list picker, opened as a modal bottom sheet — used for the
/// specialization field (36 options is too many for a plain dropdown to be usable).
Future<String?> showSearchablePicker({
  required BuildContext context,
  required String title,
  required List<String> options,
  String? selected,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SearchablePickerSheet(title: title, options: options, selected: selected),
  );
}

class _SearchablePickerSheet extends StatefulWidget {
  final String title;
  final List<String> options;
  final String? selected;
  const _SearchablePickerSheet({required this.title, required this.options, required this.selected});

  @override
  State<_SearchablePickerSheet> createState() => _SearchablePickerSheetState();
}

class _SearchablePickerSheetState extends State<_SearchablePickerSheet> {
  final _query = TextEditingController();
  late List<String> _filtered = widget.options;

  void _filter(String q) {
    setState(() {
      _filtered = q.trim().isEmpty ? widget.options : widget.options.where((o) => o.toLowerCase().contains(q.trim().toLowerCase())).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Container(
        decoration: const BoxDecoration(
          color: careloopSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(careloopRadiusLg)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: careloopBorder, borderRadius: BorderRadius.circular(999))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(children: [
                Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: careloopTextPrimary))),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop()),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _query,
                autofocus: true,
                onChanged: _filter,
                decoration: const InputDecoration(hintText: 'Search…', prefixIcon: Icon(Icons.search_rounded, size: 20)),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('No matches.', style: TextStyle(color: careloopMuted)))
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) {
                        final option = _filtered[i];
                        final isSelected = option == widget.selected;
                        return ListTile(
                          title: Text(option, style: TextStyle(color: careloopTextPrimary, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
                          trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: careloopPrimary) : null,
                          onTap: () => Navigator.of(context).pop(option),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
