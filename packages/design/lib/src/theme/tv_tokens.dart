import 'package:flutter/material.dart';

/// Measurements use a 1145 × 644 TV canvas, normalized from Apple's guide images.
abstract final class Tv26Style {
  static const canvas = Color(0xFF000000);
  static const surface = Color(0xFF1A1A1A);
  static const raisedSurface = Color(0xFF2A2A2A);
  static const border = Color(0x28FFFFFF);
  // Resting surfaces have no stroke. Remote focus is drawn separately.
  static const surfaceBorderSide = BorderSide.none;
  static const surfaceBorder = Border.fromBorderSide(surfaceBorderSide);
  static const buttonSurface = Color(0x59000000);
  static const cardPlaceholder = Color(0x09EAEAEA);
  static const modalSurface = Color(0xF01A1A1A);
  static const sidebarSurface = surface;
  static const sidebarWidth = 227.0;
  static const sidebarMargin = EdgeInsets.fromLTRB(21, 22, 0, 22);
  static const scrim = Color(0x99000000);
  static const radius = 16.0;
  static const panelRadius = 24.0;
  static const panelInset = 8.0;
  static const rowRadius = panelRadius - panelInset;
  static const menuRowHorizontalInset = 16.0;
  static const modalContentPadding = EdgeInsets.all(24);
  static const modalMenuPadding = EdgeInsets.all(panelInset);
  static const modalMenuHeaderPadding = EdgeInsets.symmetric(
    horizontal: menuRowHorizontalInset,
    vertical: gap,
  );
  static const modalShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(panelRadius)),
    side: surfaceBorderSide,
  );
  static const compactButtonHeight = 32.0;
  static const compactButtonPadding = 12.0;
  static const gap = 12.0;
  static const heroActionGap = 16.0;
  static const playerControlGap = 8.0;
  static const playerBottomInset = 2 * playerControlGap;
  static const homeHeroHeight = 524.0;
  static const detailTitleWidth = 240.0;
  static const detailTitleHeight = 48.0;
  static const detailTitleTop = sectionGap;
  static const detailHeaderGap = gap * 2;
  static const sectionGap = 32.0;
  static const focusGap = 3.0;
  static const focusWidth = 3.0;
  static const focusOutset = focusGap + focusWidth;
  static const cardRadius = 13.0;
  static const cardFocusScale = 1.02;
  static const panelBlur = 18.0;
  static const background = Color(0xFF1A1A1A);
  static const foreground = Color(0xFFEAEAEA);
  static const secondary = Color(0xFF999999);
  static const detailHeroSecondary = Color(0xFFD1D1D1);
  static const inset = 48.0;
  static const railPadding = EdgeInsets.symmetric(horizontal: inset);
  static const railItemGap = 24.0;
  static const railTitleGap = 16.0;
  static const railFadeDistance = inset - focusOutset;
  static const segmentInset = 2.0;

  static TextStyle get sectionTitle =>
      text(22, color: secondary, weight: FontWeight.w700);
  static const libraryPanelWidth = 238.0;

  static TextStyle text(
    double size, {
    Color color = foreground,
    FontWeight weight = FontWeight.w400,
    double height = 1.2,
  }) => TextStyle(
    fontFamily: 'Inter',
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: 0,
    decoration: TextDecoration.none,
    fontVariations: [FontVariation('opsz', size < 20 ? 14 : 28)],
  );
}
