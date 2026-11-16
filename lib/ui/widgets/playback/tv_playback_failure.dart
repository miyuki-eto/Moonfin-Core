import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../util/focus/key_event_utils.dart';
import '../../tv/tv26_button.dart';
import '../../tv/tv26_style.dart';
import '../../tv/tv_reveal_transition.dart';

/// A failed player keeps recovery and exit visible until the viewer acts.
class TvPlaybackFailure extends StatefulWidget {
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback onBack;

  const TvPlaybackFailure({
    super.key,
    required this.message,
    required this.onBack,
    this.onRetry,
  });

  @override
  State<TvPlaybackFailure> createState() => _TvPlaybackFailureState();
}

class _TvPlaybackFailureState extends State<TvPlaybackFailure> {
  final _back = FocusNode();
  final _retry = FocusNode();

  @override
  void dispose() {
    _back.dispose();
    _retry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FocusScope(
      onKeyEvent: (_, event) => handleBackKeyAction(event, widget.onBack),
      child: TvContentReveal(
        ready: true,
        child: ColoredBox(
          color: Tv26Style.canvas,
          child: Stack(
            children: [
              Positioned(
                top: Tv26Style.inset,
                left: Tv26Style.inset,
                child: Tv26Button(
                  label: l10n.back,
                  icon: Icons.chevron_left,
                  focusNode: _back,
                  autofocus: widget.onRetry == null,
                  onPressed: widget.onBack,
                  onDown: widget.onRetry == null ? () {} : _retry.requestFocus,
                  onUp: () {},
                  onLeft: () {},
                  onRight: () {},
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(Tv26Style.sectionGap),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.message,
                          textAlign: TextAlign.center,
                          style: Tv26Style.text(18, color: Tv26Style.secondary),
                        ),
                        if (widget.onRetry != null) ...[
                          const SizedBox(height: Tv26Style.sectionGap),
                          Tv26Button(
                            label: l10n.retry,
                            focusNode: _retry,
                            autofocus: true,
                            width: 160,
                            height: 44,
                            onPressed: widget.onRetry!,
                            onUp: _back.requestFocus,
                            onDown: () {},
                            onLeft: () {},
                            onRight: () {},
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
