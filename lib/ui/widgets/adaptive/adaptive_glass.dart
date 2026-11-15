import 'package:flutter/widgets.dart';

import '../../../util/platform_detection.dart';
import '../../tv/tv_modal.dart';

import 'package:moonfin_design/moonfin_design.dart';

import '../../../util/idiom/glass_capability.dart';

/// Renders [child] on a glass pane when the glass look applies (Apple idiom,
/// leanback Apple styling, or the glass theme on any platform), at the tier
/// resolved for this device: frost or liquid blur on capable hardware,
/// zero-blur sheen on TV boxes and web, flat [fallbackColor] otherwise.
///
/// Pass [context] where available so real blurs join the surrounding
/// [BackdropGroup] and share a single backdrop pass.
Widget adaptiveGlass({
  required Widget child,
  required Color fallbackColor,
  double cornerRadius = 16,
  double blur = 16,
  Color? tint,
  BuildContext? context,
}) {
  if (PlatformDetection.isTV) {
    return TvModalPanel(
      padding: EdgeInsets.zero,
      cornerRadius: cornerRadius,
      child: child,
    );
  }
  return glassPane(
    tier: GlassCapability.glassLookActive
        ? GlassSettings.tier
        : GlassTier.solid,
    fallbackColor: fallbackColor,
    cornerRadius: cornerRadius,
    sigma: blur,
    tint: tint,
    context: context,
    child: child,
  );
}
