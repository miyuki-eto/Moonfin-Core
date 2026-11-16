import 'package:flutter/cupertino.dart';

import '../tv/tv26_style.dart';
import '../tv/tv26_button.dart';

/// The collapsed TV navigation entry; route and expansion state stay in the sidebar.
class TvNavigationButton extends StatelessWidget {
  final FocusNode focusNode;
  final String label;
  final IconData icon;
  final VoidCallback onOpen;
  final VoidCallback onExitRight;

  const TvNavigationButton({
    super.key,
    required this.focusNode,
    required this.label,
    required this.icon,
    required this.onOpen,
    required this.onExitRight,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(
        CupertinoIcons.chevron_left,
        size: 11,
        color: Tv26Style.foreground,
      ),
      const SizedBox(width: 1),
      Tv26Button(
        label: label,
        focusNode: focusNode,
        skipTraversal: true,
        onPressed: onOpen,
        onRight: onExitRight,
        width: label.length > 5 ? 112 : 103,
        height: 36,
        fontSize: 16,
        horizontalPadding: 3,
        contentAlignment: MainAxisAlignment.start,
        leading: Container(
          width: 29,
          height: 29,
          decoration: const BoxDecoration(
            color: Color(0xFF454545),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: Tv26Style.foreground),
        ),
      ),
    ],
  );
}
