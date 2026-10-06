import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Stile dell'app: caldo ed elegante (salone), con il colore del marchio come accento.
/// Titoli in Fraunces, testo in DM Sans. Su iOS: transizioni e scorrimento nativi.
class Tema {
  static const font = 'DMSans';
  static const fontTitoli = 'Fraunces';

  static ThemeData crea({required Color primario, required Brightness luminosita}) {
    final scuro = luminosita == Brightness.dark;
    final schema = ColorScheme.fromSeed(
      seedColor: primario,
      brightness: luminosita,
      surface: scuro ? const Color(0xFF181314) : const Color(0xFFFBF8F7),
    ).copyWith(
      primary: scuro ? Color.lerp(primario, Colors.white, 0.25) : primario,
      onPrimary: _testoSu(primario),
      surfaceContainerLowest: scuro ? const Color(0xFF1E1819) : Colors.white,
      surfaceContainerLow: scuro ? const Color(0xFF231C1D) : const Color(0xFFF7F1F0),
      surfaceContainer: scuro ? const Color(0xFF2A2223) : const Color(0xFFF2EAE9),
      outlineVariant: scuro ? const Color(0xFF3D3334) : const Color(0xFFE8DCDB),
    );
    final base = ThemeData(useMaterial3: true, colorScheme: schema, fontFamily: font, brightness: luminosita);
    final testo = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(fontFamily: fontTitoli, fontWeight: FontWeight.w600, letterSpacing: -0.5),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(fontFamily: fontTitoli, fontWeight: FontWeight.w600, letterSpacing: -0.4),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontFamily: fontTitoli, fontWeight: FontWeight.w600, letterSpacing: -0.3),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
    final forma = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    return base.copyWith(
      textTheme: testo,
      scaffoldBackgroundColor: schema.surface,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      }),
      appBarTheme: AppBarTheme(
        backgroundColor: schema.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: testo.titleLarge?.copyWith(color: schema.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: schema.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: schema.outlineVariant)),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(48, 48), shape: forma, textStyle: testo.labelLarge)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48), shape: forma, side: BorderSide(color: schema.outlineVariant), textStyle: testo.labelLarge)),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(44, 44), shape: forma, textStyle: testo.labelLarge)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: schema.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: schema.outlineVariant)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: schema.outlineVariant)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: schema.primary, width: 2)),
      ),
      chipTheme: base.chipTheme.copyWith(shape: const StadiumBorder(), side: BorderSide(color: schema.outlineVariant), labelStyle: testo.labelLarge),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: schema.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: schema.primary.withValues(alpha: 0.14),
        labelTextStyle: WidgetStatePropertyAll(testo.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
        height: 68,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: schema.surfaceContainerLowest,
        indicatorColor: schema.primary.withValues(alpha: 0.14),
        selectedLabelTextStyle: testo.labelLarge?.copyWith(color: schema.primary),
      ),
      dividerTheme: DividerThemeData(color: schema.outlineVariant, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: schema.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16), minVerticalPadding: 10),
      cupertinoOverrideTheme: CupertinoThemeData(primaryColor: schema.primary),
    );
  }

  static Color _testoSu(Color c) => c.computeLuminance() > 0.45 ? const Color(0xFF1D1516) : Colors.white;
  static Color testoSu(Color c) => _testoSu(c);
}

/// Spaziature coerenti.
class S {
  static const double xs = 4, s = 8, m = 12, l = 16, xl = 24, xxl = 32;
}

bool eTablet(BuildContext c) => MediaQuery.sizeOf(c).shortestSide >= 600;
bool eLargo(BuildContext c) => MediaQuery.sizeOf(c).width >= 900;
