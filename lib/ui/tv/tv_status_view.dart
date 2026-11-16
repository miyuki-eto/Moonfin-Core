import 'package:flutter/widgets.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../l10n/app_localizations.dart';
import 'tv26_button.dart';

/// Empty and failed catalogue requests retain the same typography and retry
/// control as the rest of the TV interface.
class TvStatusView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final FocusNode? retryFocusNode;
  final VoidCallback? onRetryLeft;
  const TvStatusView({
    super.key,
    required this.message,
    this.onRetry,
    this.retryFocusNode,
    this.onRetryLeft,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Tv26Style.sectionGap),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: Tv26Style.text(
                18,
                color: Tv26Style.secondary,
                height: 1.45,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: Tv26Style.sectionGap),
              Tv26Button(
                focusNode: retryFocusNode,
                onLeft: onRetryLeft,
                label: AppLocalizations.of(context).retry,
                onPressed: onRetry!,
                width: 160,
                height: 44,
                fontSize: 18,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
