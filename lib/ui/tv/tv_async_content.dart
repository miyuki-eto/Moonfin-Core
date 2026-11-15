import 'package:flutter/widgets.dart';

import '../widgets/startup_loading.dart';
import 'tv_reveal_transition.dart';

/// Reveals the first response and claims usable focus after delayed loads.
/// Refreshes retain both the visible composition and its current focus.
class TvAsyncContent extends StatefulWidget {
  final bool ready;
  final Widget child;
  final FocusNode? initialFocusNode;
  final bool requestFocusWhenReady;
  const TvAsyncContent({
    super.key,
    required this.ready,
    required this.child,
    this.initialFocusNode,
    this.requestFocusWhenReady = true,
  });
  @override
  State<TvAsyncContent> createState() => _TvAsyncContentState();
}

class _TvAsyncContentState extends State<TvAsyncContent> {
  final _content = FocusNode(canRequestFocus: false, skipTraversal: true);
  bool _presented = false;

  void _claimFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.requestFocusWhenReady ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      final current = FocusManager.instance.primaryFocus;
      // A user may have opened the sidebar while this request was pending.
      // Preserve any usable control, including one outside the loaded body.
      if (current != _content &&
          current?.traversalDescendants.isEmpty == true) {
        return;
      }
      final preferred = widget.initialFocusNode;
      if (preferred?.context != null && preferred!.canRequestFocus) {
        preferred.requestFocus();
      } else {
        final first = _content.traversalDescendants
            .where(
              (node) =>
                  node.canRequestFocus && node.traversalDescendants.isEmpty,
            )
            .firstOrNull;
        first?.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_presented && widget.ready) {
      _presented = true;
      _claimFocus();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: !_presented,
          child: IgnorePointer(
            ignoring: !_presented,
            child: Focus(
              focusNode: _content,
              child: TvContentReveal(ready: _presented, child: widget.child),
            ),
          ),
        ),
        if (!_presented) const StartupLoading(),
      ],
    );
  }
}
