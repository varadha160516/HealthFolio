/// Renders a parameter's resolved reference range as short display text, matching Section 4.6's
/// five range_type behaviours — used anywhere a value is shown so a member never sees a bare
/// number without knowing what's normal (Overview, Trends, Health Analysis).
String formatReferenceRange(String? rangeType, Map<String, dynamic>? range) {
  if (range == null) return '';
  final low = range['low'];
  final high = range['high'];
  switch (rangeType) {
    case 'fixed_range':
      if (low != null && high != null) return '$low–$high';
      return '';
    case 'open_upper_bound':
    case 'open_lower_bound':
      // Only the lower bound is ever enforced for these two types (Section 4.6) — there's no
      // real ceiling to show, so "≥ low" is the whole story either way.
      return low != null ? '≥ $low' : '';
    case 'interpretive_rule':
    case 'qualitative':
    case 'none':
    default:
      return ''; // no automated range/flag for these (clinical-safety rule, Section 4.6)
  }
}

/// The word a LedgerFlag shows for an out-of-range value — "High"/"Low" when the direction is
/// derivable from the resolved range, "Out of range" otherwise. Never just a color: this is the
/// literal, colorblind-safe signal the design system requires (Section 3.3/5).
String flagWord(String inRangeFlag, String? rangeType, num? value, Map<String, dynamic>? range) {
  if (inRangeFlag != 'out_of_range') return 'In range';
  if (value == null || range == null) return 'Out of range';
  final low = range['low'] as num?;
  final high = range['high'] as num?;
  if (rangeType == 'fixed_range' && low != null && high != null) {
    if (value < low) return 'Low';
    if (value > high) return 'High';
  }
  if ((rangeType == 'open_lower_bound') && low != null && value < low) return 'Low';
  if ((rangeType == 'open_upper_bound') && low != null && value < low) return 'Low';
  return 'Out of range';
}
