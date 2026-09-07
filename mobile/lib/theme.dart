import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'widgets/borderless_input_border.dart';

// ---------------------------------------------------------------------------
// Gradient palette — a full replacement of the navy/periwinkle system, per a colorful
// glassmorphic reference screenshot: a soft indigo-purple-pink gradient wash, a gradient primary
// (buttons/avatars/FAB), and a distinct pastel accent color PER CATEGORY (blue, purple, pink,
// teal, orange, green) instead of one dominant ink color for everything. This reintroduces the
// two-tone split an earlier round's comments anticipated: careloopPrimary (vivid, for fills) and
// careloopTextPrimary (dark neutral ink, for reading) now genuinely diverge again, rather than
// aliasing the same value. Names are kept stable across the app's theme iterations so this file
// alone changes the whole app's look; a few genuinely new roles (teal, green) are added as new
// tokens since the old palette had no equivalent.
// ---------------------------------------------------------------------------

const careloopBg = Color(0xFFF6F3FC); // main app background fallback — a solid version of the
// gradient wash's lightest stop, for anywhere a flat Color is required (e.g. scaffoldBackgroundColor,
// which can't hold a gradient) — GlassScaffold paints the real gradient over this.
const careloopBgGradient = [Color(0xFFEEF1FC), Color(0xFFF3EEFC), Color(0xFFFBF7FE)]; // top-to-bottom
const careloopSurface = Color(0xFFFFFFFF); // default card fill — white, distinguished from the
// gradient page background by shadow alone. Cards that should stand out use the pastel tokens below.
const careloopSurfaceRaised = Color(0xFFE4E8FD); // input fields — soft indigo.
const careloopBorder = Color(0xFFECE9F7); // subtle borders and dividers.

const careloopPrimary = Color(0xFF6D5DF6); // vivid indigo-purple — buttons, FAB, selected nav
// icons, links. The dominant "brand" color; text uses careloopTextPrimary instead (see below).
const careloopPrimaryDark = Color(0xFF4C3FD1); // pressed/hover state.
const careloopPrimaryLight = Color(0xFF9D5FEA); // the gradient's second stop.
const careloopPrimaryGlow = Color(0xFFFDE4EE); // pale pink wash — icon badges.
// The brand gradient itself, for the handful of hero spots (avatar, FAB, primary CTA) drawn with
// a real LinearGradient rather than a flat careloopPrimary fill.
const careloopPrimaryGradient = [Color(0xFF6D5DF6), Color(0xFF9D5FEA), Color(0xFFE86BC4)];

const careloopAccent = Color(0xFF4C5FE0); // indigo-blue — focused inputs, selected chips/cards,
// links/secondary actions. Distinct from careloopPrimary's purple so the two roles don't collapse.
const careloopAccentDark = Color(0xFF4C3FD1);
const careloopAccentLight = Color(0xFFE4E8FD);

// The named pastel family — one color per health-information category, matched to the reference's
// own per-icon coloring (not a single rotating set anymore, but still usable that way — member
// cards, Vitals metric cards, demo-account chips — where a category doesn't apply).
const careloopLavender = Color(0xFFEEE4FB);
const careloopPeriwinkle = Color(0xFFDCEAFB);
const careloopBlush = Color(0xFFFDE4EE);
const careloopCream = Color(0xFFE4E8FD);
const careloopLilac = Color(0xFFEEE4FB);
const careloopTeal = Color(0xFF14B8A6); // health timeline / lab-related.
const careloopTealBg = Color(0xFFDFF7F0);
const careloopOrange = Color(0xFFE8863C); // symptoms / medications / address.
const careloopOrangeBg = Color(0xFFFDEBDD);
const careloopGreen = Color(0xFF22B36B); // upload / positive confirmations.
const careloopGreenBg = Color(0xFFDFF7E8);

// The app's chrome — app bar, bottom nav, the member profile screen's left-nav/right-detail
// panels — plain white cards on the gradient body; the left nav's SELECTED item now gets a light
// tint in that item's own category color (set per-item in member_profile_screen.dart), not one
// shared dark fill, so careloopPanelSelectedFill is a light indigo fallback for wherever a single
// selected-state color is still needed (e.g. the bottom NavigationBar's indicator).
const careloopPanelFill = Color(0xFFFFFFFF);
const careloopPanelBorder = Color(0xFFECE9F7);
const careloopPanelLabel = Color(0xFF8A87A3); // unselected nav icon/label — muted cool gray.
const careloopPanelSelectedFill = Color(0xFFE4E8FD);
const List<BoxShadow> careloopPanelShadow = [
  BoxShadow(color: Color(0x24503CB4), blurRadius: 18, offset: Offset(0, 8)),
];

/// The button/FAB/selected-pill fill color — the vivid brand purple. Kept as its own named token
/// (rather than deleted) since call sites across the app already reference careloopSage/
/// careloopOnSage for "the button color" specifically.
const careloopSage = Color(0xFF6D5DF6);
const careloopSageDark = Color(0xFF4C3FD1);
const careloopOnSage = Colors.white;

const careloopTextPrimary = Color(0xFF241E3D); // primary text — a dark neutral ink, DIVERGED from
// careloopPrimary's vivid purple: the reference reads body text in a near-black ink and reserves
// the bright color for fills (buttons, badges, avatars), not for text itself.
const careloopMuted = Color(0xFF7C7A94); // secondary text.
const careloopMutedDim = Color(0xFF8A87A3);

// Status colors, matched to the reference's own per-category coloring.
const careloopDanger = Color(0xFFE85C97); // muted pink — alerts, out-of-range, destructive.
const careloopAbnormalBg = Color(0xFFFDE4EE);
const careloopSuccess = Color(0xFF8B5CF6); // muted purple, matching the reference's
// "Scheduled"-style pill.
const careloopSuccessBg = Color(0xFFEEE4FB);
const careloopWarning = Color(0xFFE8863C); // warm orange — kept distinct from the cool palette so
// a warning still reads differently from info/success.
const careloopWarningBg = Color(0xFFFDEBDD);
const careloopInfo = Color(0xFF2E6FE0); // muted blue, matching the reference's "Completed"-style
// pill — distinct from careloopSuccess's purple so two different statuses read differently.
const careloopNewBg = Color(0xFFDCEAFB);

// Rounded, generous cards (16-22px).
const careloopRadiusSm = 12.0; // small controls — buttons, inputs
const careloopRadiusMd = 16.0; // cards, panels
const careloopRadiusLg = 20.0; // prominent cards, sheets
const careloopRadiusXl = 24.0; // the login hero card, dialogs
const careloopRadiusPill = 999.0; // pills — chips, tags, status badges

/// Extra bottom padding for any scrollable screen that sits under a persistent
/// FloatingActionButton (HomeShell's chat FAB, MemberProfileScreen's own) — a standard FAB is
/// ~56px plus its ~16px margin from the screen edge, and Scaffold does NOT automatically pad
/// scrollable body content to clear it, so without this the FAB visually overlaps whatever ends
/// up at the bottom of the list. Found as a real bug: the FAB was sitting directly on top of the
/// last family member's card and the last appointment row's status pill.
const careloopFabClearance = 96.0;

// Sized up a step across the board — the reference screenshot reads noticeably bigger/bolder
// (the header name, the big stat numbers) than CareLoop's previous type scale.
const careloopTypeMicro = 11.0;
const careloopTypeCaption = 13.0;
const careloopTypeBody = 15.5;
const careloopTypeSubtitle = 17.0;
const careloopTypeTitle = 20.0;
const careloopTypeTitleLg = 24.0;
const careloopTypeHero = 30.0;
const careloopTypeDisplay = 34.0;

/// A hairline border every card gets.
final Border careloopCardBorder = Border.all(color: careloopBorder, width: 1);

/// Soft, navy-tinted shadow — a single restrained lift, not a heavy drop shadow.
const List<BoxShadow> careloopCardShadow = [
  BoxShadow(color: Color(0x14503CB4), blurRadius: 14, offset: Offset(0, 3)),
];

/// A slightly stronger version for the one hero surface per screen (the login card, a presented
/// sheet) — still soft and restrained, not a dramatic elevation jump.
const List<BoxShadow> careloopRaisedShadow = [
  BoxShadow(color: Color(0x1F503CB4), blurRadius: 28, offset: Offset(0, 10)),
];

/// Page title — the one big confident heading per screen. Whole-app type system: Inter
/// everywhere, with a strict weight hierarchy instead of a separate display face — 700 for major
/// headings (this + careloopSectionHeading), 600 for health values/test names (careloopDataInline
/// already defaults there), 500 for labels (careloopEyebrow), 400 for supporting text (the
/// default body weight Material's own text theme already uses). Fairly spacious on purpose —
/// health records are numbers-heavy, so readability wins over density.
TextStyle careloopPageTitle({Color color = careloopTextPrimary, bool italic = false}) =>
    GoogleFonts.inter(fontSize: careloopTypeDisplay, height: 1.2, fontWeight: FontWeight.w700, color: color, letterSpacing: -0.2, fontStyle: italic ? FontStyle.italic : FontStyle.normal);

/// Section heading — same treatment, one size down.
TextStyle careloopSectionHeading({Color color = careloopTextPrimary, bool italic = false}) =>
    GoogleFonts.inter(fontSize: careloopTypeTitle, height: 1.3, fontWeight: FontWeight.w700, color: color, letterSpacing: -0.1, fontStyle: italic ? FontStyle.italic : FontStyle.normal);

/// Eyebrow/label — small uppercase micro-text.
TextStyle careloopEyebrow({Color color = careloopMuted}) =>
    GoogleFonts.inter(fontSize: careloopTypeMicro, height: 1.4, fontWeight: FontWeight.w500, color: color, letterSpacing: 0.6);

/// Data figures — tabular numerals via the tabular-figure OpenType feature, so columns of numbers
/// still align cleanly without needing a separate monospace family.
TextStyle careloopDataInline({double size = careloopTypeBody, Color color = careloopTextPrimary, FontWeight weight = FontWeight.w600}) =>
    GoogleFonts.inter(fontSize: size, color: color, fontWeight: weight, fontFeatures: const [FontFeature.tabularFigures()]);

TextStyle careloopDataHero({Color color = careloopTextPrimary}) =>
    GoogleFonts.inter(fontSize: careloopTypeHero, height: 1.2, fontWeight: FontWeight.w700, color: color, fontFeatures: const [FontFeature.tabularFigures()]);

ThemeData careloopTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: careloopBg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: careloopPrimary,
      brightness: Brightness.light,
      primary: careloopPrimary,
      onPrimary: Colors.white,
      primaryContainer: careloopPrimaryGlow,
      onPrimaryContainer: careloopPrimaryDark,
      secondary: careloopAccent,
      error: careloopDanger,
      surface: Colors.white,
    ),
  );

  final uiText = GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: careloopTextPrimary, displayColor: careloopTextPrimary);

  return base.copyWith(
    textTheme: uiText.copyWith(
      bodyLarge: uiText.bodyLarge?.copyWith(height: 1.5),
      bodyMedium: uiText.bodyMedium?.copyWith(height: 1.5),
    ),
    splashFactory: InkRipple.splashFactory,
    // The actual app bar chrome is transparent — GlassAppBar paints its own solid white surface
    // (see widgets/glass.dart), so this theme just sets the text/icon colors any plain AppBar
    // would still need — navy on white.
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: careloopTextPrimary,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: careloopTextPrimary),
      actionsIconTheme: IconThemeData(color: careloopTextPrimary),
    ),
    cardTheme: CardThemeData(
      color: careloopSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(careloopRadiusMd), side: BorderSide(color: careloopBorder)),
      margin: const EdgeInsets.symmetric(vertical: 7),
      clipBehavior: Clip.antiAlias,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: careloopSage,
        foregroundColor: careloopOnSage,
        disabledBackgroundColor: careloopSage.withValues(alpha: 0.35),
        disabledForegroundColor: careloopOnSage.withValues(alpha: 0.7),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(careloopRadiusPill)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: careloopSage,
        foregroundColor: careloopOnSage,
        disabledBackgroundColor: careloopSage.withValues(alpha: 0.35),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(careloopRadiusPill)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: careloopTextPrimary,
        side: const BorderSide(color: careloopBorder, width: 1.4),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(careloopRadiusPill)),
      ),
    ),
    // Secondary actions read as links via the periwinkle accent — pastel, never a bright filled
    // button.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: careloopAccentDark,
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(careloopRadiusSm)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: careloopTextPrimary)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: careloopSurfaceRaised,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      // Always show the label floated above the field, even when empty — otherwise a label only
      // floats once the field gets a value/focus, which is exactly when BorderlessInputBorder
      // (below) starts reserving space for it; keeping it always-on avoids labels jumping/
      // resizing the field the moment someone starts typing.
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: const TextStyle(color: careloopMuted),
      hintStyle: const TextStyle(color: careloopMutedDim),
      // BorderlessInputBorder, not OutlineInputBorder — see widgets/borderless_input_border.dart
      // for why: with a real OutlineInputBorder, Flutter positions the floating label straddling
      // the border line, and since that line is invisible here (borderSide: BorderSide.none, for
      // the flat filled look), the label ends up crowding into the top edge of the field instead
      // of sitting cleanly above it. That was the real bug behind labels overlapping their fields
      // on every form in the app — fixed once here, at the theme level, so it stays fixed through
      // every later palette change.
      border: const BorderlessInputBorder(borderRadius: BorderRadius.all(Radius.circular(careloopRadiusSm))),
      enabledBorder: const BorderlessInputBorder(borderRadius: BorderRadius.all(Radius.circular(careloopRadiusSm))),
      focusedBorder: BorderlessInputBorder(borderRadius: const BorderRadius.all(Radius.circular(careloopRadiusSm)), borderSide: const BorderSide(color: careloopAccent, width: 1.8)),
      errorBorder: BorderlessInputBorder(borderRadius: const BorderRadius.all(Radius.circular(careloopRadiusSm)), borderSide: const BorderSide(color: careloopDanger)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: careloopAccentDark,
      unselectedLabelColor: careloopMuted,
      indicatorColor: careloopAccent,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13.5),
      unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13.5),
    ),
    // Bottom bar sits on the same white chrome as the app bar (GlassBottomBar). The selected
    // destination gets a light indigo pill behind the icon (careloopPanelSelectedFill) — a flat
    // pastel fill, not the dark navy fill this used to be before the palette rewrite, so the
    // selected icon needs to read in careloopPrimary now, not careloopOnSage (white): white on
    // this pale a pill was effectively invisible. Found as a real contrast bug — the palette
    // rewrite updated the pill's fill color but left the icon's on-indicator color pointing at
    // the old dark-pill assumption.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      height: 68,
      surfaceTintColor: Colors.transparent,
      indicatorColor: careloopPanelSelectedFill,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(careloopRadiusPill)),
      // The selected indicator pill wraps only the icon (Material 3 behavior) — the label always
      // sits directly on the bar's own background, so it needs a color that reads there, not the
      // icon's on-indicator color.
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => GoogleFonts.inter(
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
          color: states.contains(WidgetState.selected) ? careloopPrimary : careloopPanelLabel,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: states.contains(WidgetState.selected) ? careloopPrimary : careloopPanelLabel),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: careloopSurfaceRaised,
      selectedColor: careloopAccentLight,
      labelStyle: const TextStyle(color: careloopTextPrimary, fontSize: 13),
      side: BorderSide(color: careloopBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(careloopRadiusPill)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: careloopBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: const Color(0x1F503CB4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(careloopRadiusXl), side: BorderSide(color: careloopBorder)),
      titleTextStyle: GoogleFonts.inter(fontSize: 19, fontWeight: FontWeight.w700, color: careloopTextPrimary),
      contentTextStyle: const TextStyle(fontSize: careloopTypeBody, color: careloopTextPrimary, height: 1.5),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: careloopBg,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shadowColor: const Color(0x14503CB4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(careloopRadiusMd), side: BorderSide(color: careloopBorder)),
      textStyle: const TextStyle(color: careloopTextPrimary, fontSize: 14),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: careloopBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(careloopRadiusXl))),
    ),
    dividerTheme: DividerThemeData(color: careloopBorder, thickness: 1, space: 1),
    listTileTheme: const ListTileThemeData(iconColor: careloopMuted, textColor: careloopTextPrimary),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: careloopPrimary),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: careloopTextPrimary,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(careloopRadiusMd)),
    ),
  );
}

/// A status/flag badge — solid (not translucent, see careloopAbnormalBg's note) tinted pill with
/// a small dot. Pills are back in this system; there's no "never a filled badge" rule here.
class LedgerFlag extends StatelessWidget {
  final String label;
  final bool outOfRange;
  const LedgerFlag(this.label, {super.key, required this.outOfRange});

  @override
  Widget build(BuildContext context) {
    final color = outOfRange ? careloopDanger : careloopSuccess;
    final bg = outOfRange ? careloopAbnormalBg : careloopSuccessBg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(careloopRadiusPill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 5), decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w500, fontSize: careloopTypeCaption)),
      ]),
    );
  }
}

class StatusPill extends StatelessWidget {
  final String label;
  final PillTone tone;
  const StatusPill(this.label, {super.key, this.tone = PillTone.neutral});

  factory StatusPill.forFlag(String? flag) {
    switch (flag) {
      case 'in_range':
        return StatusPill(flag!.replaceAll('_', ' '), tone: PillTone.success);
      case 'out_of_range':
        return StatusPill(flag!.replaceAll('_', ' '), tone: PillTone.danger);
      default:
        return StatusPill((flag ?? 'no flag').replaceAll('_', ' '), tone: PillTone.neutral);
    }
  }

  factory StatusPill.forReviewStatus(String status) {
    switch (status) {
      case 'pending_review':
        return StatusPill(status.replaceAll('_', ' '), tone: PillTone.warning);
      case 'auto_accepted':
      case 'confirmed':
      case 'corrected':
        return StatusPill(status.replaceAll('_', ' '), tone: PillTone.success);
      default:
        return StatusPill(status.replaceAll('_', ' '), tone: PillTone.danger);
    }
  }

  factory StatusPill.forAppointmentStatus(String status) {
    PillTone tone;
    switch (status) {
      case 'consent_granted':
      case 'in_consultation':
        tone = PillTone.success;
        break;
      case 'consent_requested':
        tone = PillTone.warning;
        break;
      case 'consent_denied':
      case 'consent_expired':
      case 'cancelled':
        tone = PillTone.danger;
        break;
      case 'completed':
        tone = PillTone.info;
        break;
      default:
        tone = PillTone.neutral;
    }
    return StatusPill(status.replaceAll('_', ' '), tone: tone);
  }

  /// The member's own "Your appointments" list deliberately shows only three words — scheduled,
  /// cancelled, completed — rather than the full provider-side state machine (checked in, consent
  /// requested/granted, in consultation, ...). Those intermediate states are real and still drive
  /// the doctor console, but from the member's side they're all still just "your visit is
  /// scheduled" until it's actually completed or called off.
  factory StatusPill.forMemberAppointmentStatus(String status) {
    switch (status) {
      case 'completed':
        return const StatusPill('Completed', tone: PillTone.info);
      case 'cancelled':
      case 'consent_denied':
      case 'consent_expired':
        return const StatusPill('Cancelled', tone: PillTone.danger);
      default:
        return const StatusPill('Scheduled', tone: PillTone.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = switch (tone) {
      PillTone.success => (bg: careloopSuccessBg, fg: careloopSuccess),
      PillTone.danger => (bg: careloopAbnormalBg, fg: careloopDanger),
      PillTone.warning => (bg: careloopWarningBg, fg: careloopWarning),
      PillTone.info => (bg: careloopNewBg, fg: careloopInfo),
      PillTone.neutral => (bg: careloopSurfaceRaised, fg: careloopMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: colors.bg, borderRadius: BorderRadius.circular(careloopRadiusPill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(color: colors.fg, shape: BoxShape.circle)),
        Text(label, style: TextStyle(color: colors.fg, fontWeight: FontWeight.w500, fontSize: 12, letterSpacing: 0.1)),
      ]),
    );
  }
}

enum PillTone { success, danger, warning, info, neutral }
