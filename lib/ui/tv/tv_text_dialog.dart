import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../widgets/track_selector_dialog.dart';

Future<void> showTvTextDialog(
  BuildContext context, {
  required String title,
  required String text,
}) => showStyledPlayerDialog<void>(
  context,
  title: title,
  maxWidth: 640,
  showCancel: true,
  builder: (_) => _ScrollableText(text: text),
);

class _ScrollableText extends StatefulWidget {
  final String text;
  const _ScrollableText({required this.text});
  @override
  State<_ScrollableText> createState() => _ScrollableTextState();
}

class _ScrollableTextState extends State<_ScrollableText> {
  final _controller = ScrollController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final direction = event.logicalKey == LogicalKeyboardKey.arrowDown
          ? 1
          : event.logicalKey == LogicalKeyboardKey.arrowUp
          ? -1
          : 0;
      if (direction == 0 || !_controller.hasClients) {
        return KeyEventResult.ignored;
      }
      final position = _controller.position;
      final target = (position.pixels + 120 * direction).clamp(
        0.0,
        position.maxScrollExtent,
      );
      if (target == position.pixels) {
        return KeyEventResult.ignored;
      }
      _controller.animateTo(
        target,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppMotion.fast,
        curve: AppMotion.ease,
      );
      return KeyEventResult.handled;
    },
    child: SingleChildScrollView(
      controller: _controller,
      padding: Tv26Style.modalMenuHeaderPadding,
      child: Text(widget.text, style: Tv26Style.text(18, height: 1.5)),
    ),
  );
}
