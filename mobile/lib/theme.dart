import 'package:material_ui/material_ui.dart';

/// Tokens from contracts/DESIGN.md (Gojek Asphalt). Use these, not raw colours, in feature code.
abstract final class GoSafeColors {
  // Brand
  static const brand = Color(
    0xFF00AA13,
  ); // Gojek green: brand moments, large text, focus
  static const brandStrong = Color(
    0xFF008A10,
  ); // fills with normal-size text (AA 4.5:1)
  static const brandDeep = Color(0xFF257226); // pressed, green text on white
  static const brandTint = Color(0xFFE6F7E8);

  // Gojek ride screen, measured from the app's screenshots (contracts/DESIGN.md "Mobile ride screen").
  static const ride = Color(
    0xFF3B8628,
  ); // call/chat circles, ETA banner, Edit outline
  static const rideIcon = Color(0xFF4CA734); // GoRide and pickup circles
  static const dropoff = Color(0xFFE16E2C);
  static const gopay = Color(0xFF4BA4CA);
  static const helpBlue = Color(0xFF4EA8C8);
  static const helpOrange = Color(0xFFE8A139);
  static const handle = Color(0xFFC8C9CE);
  static const label = Color(
    0xFF858585,
  ); // "Pickup location", small grey labels
  // The drawn map (ride_map.dart), measured from Gojek's map.
  static const mapBg = Color(0xFFE8F0F3);
  static const mapBlock = Color(0xFFD7E8EE);
  static const mapBlockLight = Color(0xFFE2ECF1);
  static const mapDot = Color(0xFF2F80ED); // "you are here"
  static const mapRoad = Color(0xFFF9FCFF);
  static const mapRoadEdge = Color(0xFFD3E2E8);
  static const mapWater = Color(0xFF8CCDFA);
  static const mapPark = Color(0xFFC2E993);

  // Neutrals (light / dark)
  static const canvas = Color(0xFFFFFFFF);
  static const canvasDark = Color(0xFF121212);
  static const surface = Color(0xFFF7F7F7);
  static const surfaceDark = Color(0xFF1C1C1C);
  static const line = Color(0xFFD9D9D6);
  static const lineSoft = Color(
    0xFFE8E8E8,
  ); // brand book neutral: the thin border on Gojek cards
  static const lineDark = Color(0xFF2E2E2E);
  static const ink = Color(0xFF101820);
  static const fgDark = Color(0xFFF2F2F2);
  static const muted = Color(0xFF63666A);
  static const mutedDark = Color(0xFFA3A3A3);

  // Safety meaning: same as the dashboard, never decorative.
  static const warn = Color(0xFFFF8F1C); // ink text only
  static const warnTint = Color(0xFFFFF4E5);
  static const unsafe = Color(0xFFE35205); // ink text only
  static const high = Color(0xFFD22730);
  static const highTint = Color(0xFFF2D4D7);
  static const sos = Color(0xFF862633);
}

/// Asphalt elevation: two levels, light straight above the screen, so shadows are soft and even.
abstract final class GoSafeShadow {
  static const low = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
  static const high = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, 8)),
  ];
}

/// Asphalt type scale: base 12, x1.3, line height rounded to 4.
abstract final class GoSafeType {
  static const titleLarge = TextStyle(
    fontSize: 34,
    height: 44 / 34,
    fontWeight: FontWeight.w700,
  );
  static const titleMedium = TextStyle(
    fontSize: 26,
    height: 36 / 26,
    fontWeight: FontWeight.w700,
  );
  static const titleSmall = TextStyle(
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
  );
  static const titleTiny = TextStyle(
    fontSize: 16,
    height: 20 / 16,
    fontWeight: FontWeight.w600,
  );
  static const bodyModerate = TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
  );
  static const bodySmall = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );
  static const caption = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
  );
}

/// The app theme. `fontFamily` is Plus Jakarta Sans in the app (stand-in for Maison Neue); tests leave it null.
ThemeData goSafeTheme(Brightness brightness, {String? fontFamily}) {
  final dark = brightness == Brightness.dark;
  final fg = dark ? GoSafeColors.fgDark : GoSafeColors.ink;
  final line = dark ? GoSafeColors.lineDark : GoSafeColors.line;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: GoSafeColors.brandStrong,
    onPrimary: Colors.white,
    secondary: GoSafeColors.brand,
    onSecondary: Colors.white,
    error: GoSafeColors.high,
    onError: Colors.white,
    surface: dark ? GoSafeColors.canvasDark : GoSafeColors.canvas,
    onSurface: fg,
    surfaceContainerHighest: dark
        ? GoSafeColors.surfaceDark
        : GoSafeColors.surface,
    onSurfaceVariant: dark ? GoSafeColors.mutedDark : GoSafeColors.muted,
    outline: line,
    outlineVariant: line,
  );
  const pill = StadiumBorder();
  const buttonText = GoSafeType.titleTiny;

  return ThemeData(
    colorScheme: scheme,
    fontFamily: fontFamily,
    // Gojek screens: white cards on a light grey page.
    scaffoldBackgroundColor: dark
        ? GoSafeColors.canvasDark
        : GoSafeColors.surface,
    textTheme: TextTheme(
      headlineMedium: GoSafeType.titleLarge,
      titleLarge: GoSafeType.titleMedium,
      titleMedium: GoSafeType.titleSmall,
      titleSmall: GoSafeType.titleTiny,
      bodyLarge: GoSafeType.bodyModerate,
      bodyMedium: GoSafeType.bodyModerate,
      bodySmall: GoSafeType.bodySmall,
      labelLarge: GoSafeType.titleTiny,
      labelMedium: GoSafeType.caption.copyWith(fontWeight: FontWeight.w600),
    ).apply(bodyColor: fg, displayColor: fg),
    // Green header with a curved bottom, as in the Gojek app.
    appBarTheme: AppBarTheme(
      backgroundColor: GoSafeColors.brandStrong,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      titleTextStyle: GoSafeType.titleSmall.copyWith(
        color: Colors.white,
        fontFamily: fontFamily,
        fontWeight: FontWeight.w700,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        side: WidgetStatePropertyAll(BorderSide(color: line)),
        textStyle: const WidgetStatePropertyAll(buttonText),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? GoSafeColors.brandTint
              : scheme.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? GoSafeColors.brandDeep : fg,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: pill,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: pill,
        side: BorderSide(color: line),
        foregroundColor: fg,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: GoSafeColors.brandDeep,
        textStyle: buttonText,
        shape: pill,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: line),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: GoSafeType.titleSmall.copyWith(
        color: fg,
        fontFamily: fontFamily,
      ),
      contentTextStyle: GoSafeType.bodyModerate.copyWith(
        color: fg,
        fontFamily: fontFamily,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(color: line),
      labelStyle: GoSafeType.caption.copyWith(
        fontWeight: FontWeight.w600,
        color: fg,
      ),
    ),
    bannerTheme: MaterialBannerThemeData(
      backgroundColor: dark ? GoSafeColors.surfaceDark : GoSafeColors.surface,
      contentTextStyle: GoSafeType.bodySmall.copyWith(
        color: fg,
        fontFamily: fontFamily,
      ),
      dividerColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(color: line, thickness: 1),
  );
}
