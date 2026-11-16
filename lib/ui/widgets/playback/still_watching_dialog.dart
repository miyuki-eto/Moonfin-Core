import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../l10n/app_localizations.dart';
import '../../../util/platform_detection.dart';
import '../../tv/tv26_button.dart';
import '../../tv/tv_modal.dart';
import '../adaptive/adaptive_glass.dart';
import '../overlay_sheet.dart';

class StillWatchingDialog extends StatelessWidget {
  final VoidCallback onContinue;
  final VoidCallback onStop;

  const StillWatchingDialog({
    super.key,
    required this.onContinue,
    required this.onStop,
  });

  static Future<bool?> show(BuildContext context) {
    return showFocusRestoringDialog<bool>(
      context: context,
      barrierDismissible: false,
      // Popped through the dialog's own context. The caller's would target
      // whichever navigator the caller sits in, taking that route down instead
      // and leaving the answer unresolved.
      builder: (dialogContext) => StillWatchingDialog(
        onContinue: () => Navigator.pop(dialogContext, true),
        onStop: () => Navigator.pop(dialogContext, false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (PlatformDetection.isTV) {
      return Dialog(
        backgroundColor: Colors.transparent,
        child: TvModalPanel(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.stillWatching,
                textAlign: TextAlign.center,
                style: Tv26Style.text(28, weight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.stillWatchingContent,
                textAlign: TextAlign.center,
                style: Tv26Style.text(18, color: Tv26Style.secondary),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tv26Button(
                    label: l10n.stillWatchingContinue,
                    autofocus: true,
                    onPressed: onContinue,
                  ),
                  const SizedBox(width: Tv26Style.gap),
                  Tv26Button(label: l10n.stillWatchingStop, onPressed: onStop),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: adaptiveGlass(
          context: context,
          cornerRadius: 24,
          blur: 30,
          fallbackColor: AppColorScheme.surface.withValues(alpha: 0.62),
          tint: AppColorScheme.surface.withValues(alpha: 0.22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColorScheme.accent.withValues(alpha: 0.16),
                    border: Border.all(
                      color: AppColorScheme.accent.withValues(alpha: 0.4),
                      width: 0.5,
                    ),
                  ),
                  child: Icon(
                    Icons.visibility_outlined,
                    color: AppColorScheme.accent,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.stillWatching,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColorScheme.onSurface,
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.stillWatchingContent,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColorScheme.onSurface.withValues(alpha: 0.62),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  autofocus: true,
                  onPressed: onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColorScheme.accent,
                    foregroundColor: AppColorScheme.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(l10n.stillWatchingContinue),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: onStop,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColorScheme.onSurface.withValues(
                      alpha: 0.6,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  child: Text(l10n.stillWatchingStop),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
