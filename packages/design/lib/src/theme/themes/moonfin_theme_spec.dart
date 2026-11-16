import 'package:flutter/material.dart';
import '../theme_spec.dart';
import '../tv_tokens.dart';

const moonfinThemeSpec = ThemeSpec(
  id: 'moonfin',
  displayName: 'Moonfin',
  // Media web palette: web/src/style.css in the Media project.
  colors: ThemeColorTokens(
    background: Tv26Style.canvas,
    onBackground: Tv26Style.foreground,
    surface: Tv26Style.surface,
    onSurface: Tv26Style.foreground,
    surfaceVariant: Tv26Style.raisedSurface,
    scrim: Tv26Style.scrim,
    accent: Tv26Style.foreground,
    onAccent: Tv26Style.canvas,
    buttonNormal: Color(0xFF202024),
    buttonFocused: Tv26Style.foreground,
    buttonDisabled: Color(0xFF161618),
    buttonActive: Color(0xFF2D2D2F),
    onButtonNormal: Color(0xFFE3E4E6),
    onButtonFocused: Tv26Style.canvas,
    onButtonDisabled: Color(0xFF737680),
    inputBackground: Color(0xFF161618),
    inputFocused: Color(0xFF202024),
    inputBorder: Tv26Style.border,
    inputBorderFocused: Tv26Style.foreground,
    rangeTrack: Color(0xFF2D2D2F),
    rangeProgress: Tv26Style.foreground,
    rangeThumb: Tv26Style.foreground,
    seekbarBuffered: Color(0x80FFFFFF),
    badgeBackground: Color(0xFF161618),
    onBadge: Color(0xFFE3E4E6),
    badgeUnplayed: Color(0xFFEAEAEA),
    badgeWatched: Color(0xFF5CC181),
    recordingActive: Color(0xFFE45866),
    recordingScheduled: Color(0xFFEABC53),
  ),
  borders: ThemeBorderTokens(
    cardBorder: Tv26Style.surfaceBorderSide,
    chipBorder: Tv26Style.surfaceBorderSide,
    focusBorder: BorderSide(color: Color(0xFFE3E4E6), width: 2),
    cardRadius: BorderRadius.all(Radius.circular(14)),
    chipRadius: BorderRadius.all(Radius.circular(8)),
    chipBackground: Color(0xFF202024),
    focusGlow: [],
  ),
);
