import 'package:flutter/material.dart';

/// A fully rounded-rect input border with no visible stroke by default — visually identical to
/// an [OutlineInputBorder], but NOT one as far as label layout is concerned: [isOutline] is
/// overridden to false.
///
/// Why this matters: Flutter's [InputDecorator] positions a floating label differently depending
/// on [InputBorder.isOutline]. For a real outline border, the label is vertically centered ON the
/// border line (so the border can be drawn with a gap cut into it for the label to sit in). When
/// the border's own stroke is invisible (`borderSide: BorderSide.none`, which this app relies on
/// for its flat filled-field look), that gap is never painted — so the label still straddles
/// where the invisible line would be, with its lower half rendering inside the field, overlapping
/// the top of the filled box. That was the cause of labels crowding into every text field across
/// the app. A non-outline border reserves real space fully ABOVE the field instead.
class BorderlessInputBorder extends OutlineInputBorder {
  const BorderlessInputBorder({
    super.borderSide = BorderSide.none,
    super.borderRadius = const BorderRadius.all(Radius.circular(4)),
    super.gapPadding = 4.0,
  });

  @override
  bool get isOutline => false;

  @override
  BorderlessInputBorder copyWith({BorderSide? borderSide, BorderRadius? borderRadius, double? gapPadding}) {
    return BorderlessInputBorder(
      borderSide: borderSide ?? this.borderSide,
      borderRadius: borderRadius ?? this.borderRadius,
      gapPadding: gapPadding ?? this.gapPadding,
    );
  }
}
