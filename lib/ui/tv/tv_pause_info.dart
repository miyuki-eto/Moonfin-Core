import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import 'tv_modal.dart';
import 'tv_reveal_transition.dart';

/// Paused information shares the menu surface without taking transport focus.
class TvPauseInfo extends StatelessWidget {
  final bool visible;
  final String title;
  final String description;
  const TvPauseInfo({
    super.key,
    required this.visible,
    required this.title,
    required this.description,
  });
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.slow,
      switchInCurve: AppMotion.ease,
      switchOutCurve: AppMotion.ease,
      transitionBuilder: (child, animation) =>
          TvRevealTransition(animation: animation, child: child),
      child: !visible
          ? const SizedBox.shrink(key: ValueKey('playing'))
          : TvModalPanel(
              key: const ValueKey('paused'),
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Tv26Style.text(24, weight: FontWeight.w700),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: Tv26Style.gap),
                    Text(
                      description,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: Tv26Style.text(
                        16,
                        color: Tv26Style.secondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    ),
  );
}
