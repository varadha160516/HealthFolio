import 'package:flutter/material.dart';
import '../theme.dart';

/// A text field with a live suggestions dropdown as the user types, matching against [options],
/// with a manual "use as typed" entry always offered too (even with zero matches) so nothing this
/// field's reference list doesn't know about is ever blocked.
class AutocompleteField extends StatefulWidget {
  final String label;
  final List<String> options;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  const AutocompleteField({super.key, required this.label, required this.options, required this.controller, this.onChanged});

  @override
  State<AutocompleteField> createState() => _AutocompleteFieldState();
}

typedef _Opt = ({String value, bool manual});

class _AutocompleteFieldState extends State<AutocompleteField> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return RawAutocomplete<_Opt>(
        textEditingController: widget.controller,
        focusNode: _focusNode,
        optionsBuilder: (value) {
          final q = value.text.trim();
          if (q.isEmpty) return const Iterable<_Opt>.empty();
          final ql = q.toLowerCase();
          final matches = widget.options.where((o) => o.toLowerCase().contains(ql)).take(6).map((o) => (value: o, manual: false));
          return [...matches, (value: q, manual: true)];
        },
        displayStringForOption: (opt) => opt.value,
        onSelected: (opt) => widget.onChanged?.call(opt.value),
        fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
          return TextField(
            controller: textEditingController,
            focusNode: focusNode,
            decoration: InputDecoration(labelText: widget.label),
            onChanged: widget.onChanged,
          );
        },
        optionsViewBuilder: (context, onSelected, opts) {
          final list = opts.toList();
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              color: docSurface,
              borderRadius: BorderRadius.circular(docRadiusSm),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: 230, minWidth: constraints.maxWidth, maxWidth: constraints.maxWidth),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final o = list[i];
                    if (o.manual) {
                      return Column(mainAxisSize: MainAxisSize.min, children: [
                        if (list.length > 1) const Divider(height: 1),
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.add_circle_outline_rounded, size: 18, color: docAccentDark),
                          title: Text('Use "${o.value}" as typed', style: const TextStyle(color: docAccentDark, fontWeight: FontWeight.w600, fontSize: 13)),
                          onTap: () => onSelected(o),
                        ),
                      ]);
                    }
                    return ListTile(
                      dense: true,
                      title: Text(o.value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      onTap: () => onSelected(o),
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
    });
  }
}
