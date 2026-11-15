import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../util/platform_detection.dart';
import '../../util/focus/dpad_keys.dart';
import '../../util/focus/key_event_utils.dart';
import 'browser_view_focus_stub.dart'
    if (dart.library.js_interop) 'browser_view_focus_web.dart';

/// A browser normally scrolls with arrows. TV arrows move focus instead, just
/// as native D-pad events do. Individual controls still handle their keys first
/// (including text editing, locked rails and explicit edge handoffs).
class TvRemoteNavigation extends StatefulWidget {
  const TvRemoteNavigation({super.key, required this.child});

  final Widget child;

  @override
  State<TvRemoteNavigation> createState() => _TvRemoteNavigationState();
}

class _TvRemoteNavigationState extends State<TvRemoteNavigation> {
  final _node = FocusNode(canRequestFocus: false, skipTraversal: true);

  TraversalDirection? _direction(KeyEvent event) => switch (event.logicalKey) {
    LogicalKeyboardKey.arrowUp => TraversalDirection.up,
    LogicalKeyboardKey.arrowDown => TraversalDirection.down,
    LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
    LogicalKeyboardKey.arrowRight => TraversalDirection.right,
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_retainBrowserViewFocus);
    HardwareKeyboard.instance.addHandler(_restoreViewFocus);
  }

  void _retainBrowserViewFocus() {
    if (!PlatformDetection.isTV ||
        FocusManager.instance.primaryFocus != FocusManager.instance.rootScope ||
        !browserViewRetainsFocus) {
      return;
    }
    // Flutter parks focus at the root when web semantics reparents a focused
    // DOM node. Restore the remembered route in that same focus transaction,
    // without waiting for another remote press or reclaiming browser chrome.
    scheduleMicrotask(() {
      if (!mounted ||
          !browserViewRetainsFocus ||
          FocusManager.instance.primaryFocus !=
              FocusManager.instance.rootScope) {
        return;
      }
      _node.nearestScope?.requestFocus();
    });
  }

  // Removing a focused web semantics element can park Flutter's focus at the
  // root even though the browser still delivers keys. No descendant handler
  // receives those keys. Restore this view's remembered route, then traverse.
  bool _restoreViewFocus(KeyEvent event) {
    if (!PlatformDetection.isTV ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        FocusManager.instance.primaryFocus != FocusManager.instance.rootScope) {
      return false;
    }
    final direction = _direction(event);
    final scope = _node.nearestScope;
    if ((direction == null && !isActivateKey(event)) || scope == null) {
      return false;
    }
    scope.requestFocus();
    scheduleMicrotask(() {
      if (!mounted) return;
      FocusManager.instance.applyFocusChangesIfNeeded();
      final focus = FocusManager.instance.primaryFocus;
      if (focus == null || !focus.ancestors.contains(_node)) return;
      // The normal dispatch already ended at the root. Give the restored
      // control this one press, preserving its explicit rail/Back handlers.
      for (final node in [focus, ...focus.ancestors]) {
        if (identical(node, _node)) break;
        final result = node.onKeyEvent?.call(node, event);
        if (result != null && result != KeyEventResult.ignored) return;
      }
      if (direction != null) {
        focus.focusInDirection(direction);
      } else if (focus.context != null) {
        activateFocusedTarget(focus.context!);
      }
    });
    return true;
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_retainBrowserViewFocus);
    HardwareKeyboard.instance.removeHandler(_restoreViewFocus);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PlatformDetection.isTV
      ? Focus(
          focusNode: _node,
          canRequestFocus: false,
          skipTraversal: true,
          includeSemantics: false,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            final focus = FocusManager.instance.primaryFocus;
            // Editing shortcuts sit above MaterialApp's builder. Leave them
            // reachable rather than turning caret movement into traversal.
            if (focus?.context?.findAncestorStateOfType<EditableTextState>() !=
                null) {
              return KeyEventResult.ignored;
            }
            final direction = _direction(event);
            if (direction == null || focus == null) {
              return KeyEventResult.ignored;
            }
            focus.focusInDirection(direction);
            return KeyEventResult.handled;
          },
          child: widget.child,
        )
      : widget.child;
}
