import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../navigation/destinations.dart';
import 'tv26_button.dart';

class TvBackButton extends StatelessWidget {
  final FocusNode focusNode;
  final VoidCallback onExitToContent;

  const TvBackButton({
    super.key,
    required this.focusNode,
    required this.onExitToContent,
  });

  @override
  Widget build(BuildContext context) => Tv26Button(
    label: AppLocalizations.of(context).back,
    icon: CupertinoIcons.chevron_left,
    focusNode: focusNode,
    skipTraversal: true,
    width: 112,
    height: 36,
    fontSize: 16,
    iconSize: 16,
    onRight: onExitToContent,
    onDown: onExitToContent,
    onUp: () {},
    onLeft: () {},
    onPressed: () {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(Destinations.home);
      }
    },
  );
}
