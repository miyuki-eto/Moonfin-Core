import 'package:flutter/cupertino.dart';

import '../../l10n/app_localizations.dart';
import 'tv26_button.dart';
import 'tv26_style.dart';

/// Shared page chrome for the secondary catalog screens.
class TvBrowseHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onHome;
  final FocusNode? homeFocusNode;
  final VoidCallback? onHomeDown;
  final List<Widget> actions;
  const TvBrowseHeader({
    super.key,
    required this.title,
    required this.onHome,
    this.subtitle,
    this.homeFocusNode,
    this.onHomeDown,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Tv26Style.inset,
      30,
      Tv26Style.inset,
      24,
    ),
    child: Row(
      children: [
        Tv26Button(
          label: AppLocalizations.of(context).home,
          icon: CupertinoIcons.house_fill,
          width: 104,
          height: 36,
          fontSize: 16,
          onPressed: onHome,
          focusNode: homeFocusNode,
          onDown: onHomeDown,
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Tv26Style.text(28, weight: FontWeight.w700),
              ),
              if (subtitle?.isNotEmpty ?? false)
                Text(
                  subtitle!,
                  style: Tv26Style.text(13, color: Tv26Style.secondary),
                ),
            ],
          ),
        ),
        ...actions,
      ],
    ),
  );
}
