/// Turns a prescription line item's free-text `frequency` (as OCR'd — "Once daily", "1-0-1",
/// "SOS", ...) into a starting schedule. This is a heuristic default, not a clinical dosing
/// engine — every field it produces is editable before (Review Medicines) and after (medication
/// detail's Edit) being saved, so a wrong guess here is a two-tap fix, never silently binding.
(String frequency, List<String> times) inferMedicationSchedule(String? frequencyText) {
  final f = (frequencyText ?? '').toLowerCase().trim();

  if (f.contains('as needed') || f.contains('prn') || f.contains('sos')) return ('as_needed', const []);

  // Indian-prescription "1-0-1" / "1-1-1" style dosage notation: morning-afternoon-night counts.
  final dashMatch = RegExp(r'^(\d)\s*-\s*(\d)\s*-\s*(\d)$').firstMatch(f);
  if (dashMatch != null) {
    const slots = ['08:00', '14:00', '20:00'];
    final times = <String>[];
    for (var i = 0; i < 3; i++) {
      if (dashMatch.group(i + 1) != '0') times.add(slots[i]);
    }
    return ('daily', times.isEmpty ? const ['08:00'] : times);
  }

  if (f.contains('four times') || f.contains('qid')) return ('daily', const ['08:00', '12:00', '16:00', '20:00']);
  if (f.contains('thrice') || f.contains('three times') || f.contains('tds')) return ('daily', const ['08:00', '14:00', '20:00']);
  if (f.contains('twice') || f.contains('two times') || f.contains('bd')) return ('daily', const ['08:00', '20:00']);
  if (f.contains('weekly') || f.contains('once a week')) return ('weekly', const ['20:00']);
  if (f.contains('once') || f.contains('daily') || f.contains('od')) return ('daily', const ['08:00']);

  return ('daily', const ['08:00']);
}

String frequencyLabel(String frequency, List<String> times, int? dayOfWeek) {
  const weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  switch (frequency) {
    case 'as_needed':
      return 'As needed';
    case 'weekly':
      final day = dayOfWeek != null ? weekdays[dayOfWeek] : 'Weekly';
      return times.isEmpty ? day : '$day · ${formatTime(times.first)}';
    default:
      return switch (times.length) {
        0 => 'Daily',
        1 => 'Once daily · ${formatTime(times.first)}',
        2 => 'Twice daily',
        3 => 'Three times daily',
        _ => '${times.length} times daily',
      };
  }
}

String formatTime(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return hhmm;
  var h = int.tryParse(parts[0]) ?? 0;
  final m = parts[1];
  final suffix = h >= 12 ? 'PM' : 'AM';
  h = h % 12;
  if (h == 0) h = 12;
  return '$h:$m $suffix';
}
