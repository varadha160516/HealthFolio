import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'widgets/borderless_input_border.dart';

// Doctor Console is a separate app from HealthFolio (the member-facing app in this same
// workspace). Palette: claymorphism — soft lavender-indigo clay, cards defined by a dual
// light/dark shadow rather than a fill or a border (see docCardShadow / docCardBorder below) —
// picked over liquid-glass/neumorphism/flat directions after a mockup round.

const docBg = Color(0xFFF1EEFA);
const docBgGradient = [Color(0xFFF1EEFA), Color(0xFFF1EEFA), Color(0xFFF1EEFA)];
const docSurface = Color(0xFFF1EEFA);
const docSurfaceRaised = Color(0xFFEBE7F7);
const docBorder = Color(0xFFDAD6EC);

const docPrimary = Color(0xFF6D74D9);
const docPrimaryDark = Color(0xFF4F55B0);
const docPrimaryLight = Color(0xFF9088E3);
const docPrimaryGlow = Color(0xFFE3E0FA);
const docPrimaryGradient = [Color(0xFF6D8CFF), Color(0xFFA47AEE)];

const docAccent = Color(0xFF6D8CFF);
const docAccentDark = Color(0xFF4F63E0);
const docAccentLight = Color(0xFFDDE6FE);

const docTeal = Color(0xFF6D8CFF);
const docTealBg = Color(0xFFDDE6FE);
const docOrange = Color(0xFFC97B2E);
const docOrangeBg = Color(0xFFFDE7CE);
const docGreen = Color(0xFF0E9670);
const docGreenBg = Color(0xFFD3F3E8);

const docTextPrimary = Color(0xFF2C2D4D);
const docMuted = Color(0xFF8B8CA8);
const docMutedDim = Color(0xFFB4B5CE);

const docDanger = Color(0xFFC23D75);
const docDangerBg = Color(0xFFFBD9E8);
const docSuccess = Color(0xFF0E9670);
const docSuccessBg = Color(0xFFD3F3E8);
const docWarning = Color(0xFFC97B2E);
const docWarningBg = Color(0xFFFDE7CE);
const docInfo = Color(0xFF3B6FE0);
const docInfoBg = Color(0xFFDBE8FE);

const docRadiusSm = 14.0;
const docRadiusMd = 22.0;
const docRadiusLg = 26.0;
const docRadiusXl = 30.0;
const docRadiusPill = 999.0;

const docFabClearance = 96.0;

const docTypeMicro = 11.0;
const docTypeCaption = 13.0;
const docTypeBody = 15.5;
const docTypeSubtitle = 17.0;
const docTypeTitle = 20.0;
const docTypeTitleLg = 24.0;
const docTypeHero = 30.0;

// No border — a clay surface is the SAME color as what it sits on and reads as raised purely
// from the dual shadow below (dark toward the light source's opposite corner, a soft white
// highlight toward the light source). A transparent Border keeps every existing call site
// (`border: docCardBorder`) working unchanged.
final Border docCardBorder = Border.all(color: Colors.transparent, width: 0);

const List<BoxShadow> docCardShadow = [
  BoxShadow(color: Color(0x52A396DC), blurRadius: 15, offset: Offset(7, 7)),
  BoxShadow(color: Color(0xE6FFFFFF), blurRadius: 15, offset: Offset(-7, -7)),
];
const List<BoxShadow> docRaisedShadow = [
  BoxShadow(color: Color(0x66A396DC), blurRadius: 20, offset: Offset(9, 9)),
  BoxShadow(color: Color(0xCCFFFFFF), blurRadius: 20, offset: Offset(-8, -8)),
];

TextStyle docPageTitle({Color color = docTextPrimary}) =>
    GoogleFonts.inter(fontSize: docTypeHero, height: 1.2, fontWeight: FontWeight.w700, color: color, letterSpacing: -0.2);

TextStyle docSectionHeading({Color color = docTextPrimary}) =>
    GoogleFonts.inter(fontSize: docTypeTitle, height: 1.3, fontWeight: FontWeight.w700, color: color, letterSpacing: -0.1);

TextStyle docEyebrow({Color color = docMuted}) => GoogleFonts.inter(fontSize: docTypeMicro, height: 1.4, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.4);

ThemeData docTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: docBg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: docPrimary,
      brightness: Brightness.light,
      primary: docPrimary,
      onPrimary: Colors.white,
      secondary: docAccent,
      error: docDanger,
      surface: Colors.white,
    ),
  );
  final uiText = GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: docTextPrimary, displayColor: docTextPrimary);

  return base.copyWith(
    textTheme: uiText,
    splashFactory: InkRipple.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: docTextPrimary,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: docTextPrimary),
    ),
    cardTheme: CardThemeData(
      color: docSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(docRadiusMd), side: BorderSide.none),
      margin: const EdgeInsets.symmetric(vertical: 7),
      clipBehavior: Clip.antiAlias,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: docPrimary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: docPrimary.withValues(alpha: 0.35),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(docRadiusPill)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: docTextPrimary,
        side: const BorderSide(color: docBorder, width: 1.4),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(docRadiusPill)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: docAccentDark, textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13.5)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: docSurfaceRaised,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      // Always float the label above the field, even when empty — otherwise it only floats once
      // focused/filled, which is exactly when BorderlessInputBorder (below) starts reserving space
      // for it; keeping it always-on avoids the label jumping the moment someone starts typing.
      floatingLabelBehavior: FloatingLabelBehavior.always,
      // BorderlessInputBorder, not OutlineInputBorder — a real outline border vertically centers
      // the floating label ON the border line so a gap can be cut into it; with the stroke itself
      // invisible (borderSide: BorderSide.none, for this app's flat filled-field look) that gap is
      // never painted, so the label still straddled where the line would be, its lower half
      // rendering inside the field and overlapping the box's top edge on every screen. This is the
      // fix for that.
      border: const BorderlessInputBorder(borderRadius: BorderRadius.all(Radius.circular(docRadiusSm))),
      enabledBorder: const BorderlessInputBorder(borderRadius: BorderRadius.all(Radius.circular(docRadiusSm))),
      focusedBorder: BorderlessInputBorder(borderRadius: const BorderRadius.all(Radius.circular(docRadiusSm)), borderSide: const BorderSide(color: docAccent, width: 1.8)),
      hintStyle: const TextStyle(color: docMutedDim),
      labelStyle: const TextStyle(color: docMuted),
    ),
    dividerTheme: const DividerThemeData(color: docBorder, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: docTextPrimary,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(docRadiusMd)),
    ),
  );
}

enum PillTone { success, danger, warning, info, neutral }

class StatusPill extends StatelessWidget {
  final String label;
  final PillTone tone;
  const StatusPill(this.label, {super.key, this.tone = PillTone.neutral});

  factory StatusPill.forAppointment(String status) {
    switch (status) {
      case 'checked_in':
        return const StatusPill('Checked in', tone: PillTone.info);
      case 'consent_requested':
        return const StatusPill('Waiting', tone: PillTone.warning);
      case 'consent_granted':
        return const StatusPill('Ready', tone: PillTone.success);
      case 'in_consultation':
        return const StatusPill('In consultation', tone: PillTone.success);
      case 'completed':
        return const StatusPill('Completed', tone: PillTone.info);
      case 'consent_denied':
        return const StatusPill('Consent denied', tone: PillTone.danger);
      case 'consent_expired':
        return const StatusPill('Consent expired', tone: PillTone.danger);
      case 'cancelled':
        return const StatusPill('Cancelled', tone: PillTone.danger);
      default:
        return const StatusPill('Upcoming', tone: PillTone.neutral);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = switch (tone) {
      PillTone.success => (bg: docSuccessBg, fg: docSuccess),
      PillTone.danger => (bg: docDangerBg, fg: docDanger),
      PillTone.warning => (bg: docWarningBg, fg: docWarning),
      PillTone.info => (bg: docInfoBg, fg: docInfo),
      PillTone.neutral => (bg: docSurfaceRaised, fg: docMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: colors.bg, borderRadius: BorderRadius.circular(docRadiusPill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(color: colors.fg, shape: BoxShape.circle)),
        Text(label, style: TextStyle(color: colors.fg, fontWeight: FontWeight.w600, fontSize: 11.5)),
      ]),
    );
  }
}

class DocCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const DocCard({super.key, required this.child, this.padding = const EdgeInsets.all(14)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(color: docSurface, borderRadius: BorderRadius.circular(docRadiusMd), border: docCardBorder, boxShadow: docCardShadow),
      child: child,
    );
  }
}

class DocGradientScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  const DocGradientScaffold({super.key, this.appBar, required this.body, this.bottomNavigationBar, this.floatingActionButton});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: docBgGradient)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: appBar,
        body: body,
        bottomNavigationBar: bottomNavigationBar,
        floatingActionButton: floatingActionButton,
      ),
    );
  }
}

class LoadingCenter extends StatelessWidget {
  const LoadingCenter({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator(color: docPrimary));
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const EmptyState({super.key, required this.icon, required this.message});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(children: [
        Icon(icon, size: 40, color: docMutedDim),
        const SizedBox(height: 10),
        Text(message, style: const TextStyle(color: docMuted, fontSize: 13.5)),
      ]),
    );
  }
}
