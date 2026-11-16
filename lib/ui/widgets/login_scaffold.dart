import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import 'overlay_sheet.dart';
import '../tv/tv_modal.dart';
import '../tv/tv_reveal_transition.dart';
import '../../util/platform_detection.dart';

const _kCardMaxWidth = 700.0;

class LoginScaffold extends StatelessWidget {
  final double maxWidth;
  final Widget child;
  final Widget? header;
  final Widget? footer;

  const LoginScaffold({
    super.key,
    this.maxWidth = _kCardMaxWidth,
    this.header,
    this.footer,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Tv26Style.sectionGap),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ?header,
                TvModalPanel(
                  padding: const EdgeInsets.all(Tv26Style.sectionGap),
                  child: child,
                ),
                ?footer,
              ],
            ),
          ),
        ),
      ),
    );
    return Scaffold(
      backgroundColor: Tv26Style.canvas,
      body: PlatformDetection.isTV ? TvContentReveal(child: content) : content,
    );
  }
}

/// Sign-in pages are opened with go, so the router has nothing to pop and Back
/// would offer to exit the app, or on newer Android close it outright. This
/// hands Back to [onBack] instead, unless a dialog sits on top of the page.
class SignInBackScope extends StatefulWidget {
  final VoidCallback onBack;
  final Widget child;

  const SignInBackScope({super.key, required this.onBack, required this.child});

  @override
  State<SignInBackScope> createState() => _SignInBackScopeState();
}

class _SignInBackScopeState extends State<SignInBackScope> {
  @override
  void initState() {
    super.initState();
    InlineBackInterceptor.push(_handleBack);
  }

  @override
  void dispose() {
    InlineBackInterceptor.remove(_handleBack);
    super.dispose();
  }

  bool _handleBack() {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    widget.onBack();
    return true;
  }

  // The scope is what makes Android hand Back to the app on a first page.
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) {
        _handleBack();
      }
    },
    child: widget.child,
  );
}
