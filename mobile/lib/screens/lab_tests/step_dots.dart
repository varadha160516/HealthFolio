import 'package:flutter/material.dart';
import '../../theme.dart';

/// 4-step progress indicator shared by the Lab Tests booking flow: Tests → Date & time →
/// Who's it for → Confirm.
class LabTestStepDots extends StatelessWidget {
  final int step; // 1-indexed, 1..4
  const LabTestStepDots({super.key, required this.step});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= 4; i++) ...[
          if (i > 1) const SizedBox(width: 6),
          Container(width: 22, height: 4, decoration: BoxDecoration(color: i <= step ? careloopPrimary : careloopAccentLight, borderRadius: BorderRadius.circular(999))),
        ],
      ],
    );
  }
}
