import 'package:flutter/material.dart';

/// The app's palette, carried on [ThemeData] as an extension so widgets read
/// one object rather than reaching for a dozen unrelated Material slots.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.card,
    required this.cardPressed,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.up,
    required this.down,
    required this.flat,
    required this.accent,
    required this.danger,
  });

  final Color bg;
  final Color card;
  final Color cardPressed;
  final Color border;
  final Color text;
  final Color textMuted;
  final Color textFaint;
  final Color up;
  final Color down;
  final Color flat;
  final Color accent;
  final Color danger;

  /// Colour for a change value: green up, red down, muted when unchanged.
  Color trend(double change) {
    if (!change.isFinite || change == 0) return flat;
    return change > 0 ? up : down;
  }

  static const light = AppColors(
    bg: Color(0xFFF5F6F8),
    card: Color(0xFFFFFFFF),
    cardPressed: Color(0xFFECEEF1),
    border: Color(0xFFE2E5EA),
    text: Color(0xFF0B0F14),
    textMuted: Color(0xFF5C6672),
    textFaint: Color(0xFF9AA3AE),
    up: Color(0xFF0F9D58),
    down: Color(0xFFD93025),
    flat: Color(0xFF5C6672),
    accent: Color(0xFF1A73E8),
    danger: Color(0xFFD93025),
  );

  static const dark = AppColors(
    bg: Color(0xFF0B0F14),
    card: Color(0xFF151B23),
    cardPressed: Color(0xFF1E262F),
    border: Color(0xFF232C36),
    text: Color(0xFFF2F5F8),
    textMuted: Color(0xFF98A3B0),
    textFaint: Color(0xFF6B7683),
    up: Color(0xFF31C48D),
    down: Color(0xFFF05252),
    flat: Color(0xFF98A3B0),
    accent: Color(0xFF5B9DF9),
    danger: Color(0xFFF05252),
  );

  @override
  AppColors copyWith({
    Color? bg,
    Color? card,
    Color? cardPressed,
    Color? border,
    Color? text,
    Color? textMuted,
    Color? textFaint,
    Color? up,
    Color? down,
    Color? flat,
    Color? accent,
    Color? danger,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      card: card ?? this.card,
      cardPressed: cardPressed ?? this.cardPressed,
      border: border ?? this.border,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      up: up ?? this.up,
      down: down ?? this.down,
      flat: flat ?? this.flat,
      accent: accent ?? this.accent,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardPressed: Color.lerp(cardPressed, other.cardPressed, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      up: Color.lerp(up, other.up, t)!,
      down: Color.lerp(down, other.down, t)!,
      flat: Color.lerp(flat, other.flat, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

/// Reads the palette for the current brightness. Every widget in the app goes
/// through this rather than hard-coding colours.
extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

ThemeData buildTheme(AppColors c, Brightness brightness) {
  final base = ThemeData(brightness: brightness, useMaterial3: true);

  return base.copyWith(
    extensions: [c],
    scaffoldBackgroundColor: c.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: brightness,
    ).copyWith(surface: c.bg, primary: c.accent, error: c.danger),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: c.text,
        fontSize: 19,
        fontWeight: FontWeight.w600,
      ),
    ),
    dividerColor: c.border,
    textTheme: base.textTheme.apply(bodyColor: c.text, displayColor: c.text),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.textMuted),
  );
}

final lightTheme = buildTheme(AppColors.light, Brightness.light);
final darkTheme = buildTheme(AppColors.dark, Brightness.dark);

/// Tabular figures, so a changing price does not shuffle the digits around it.
const tabularFigures = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
