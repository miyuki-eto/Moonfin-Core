import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../l10n/app_localizations.dart';
import '../../navigation/destinations.dart';
import '../../tv/tv26_button.dart';

/// The same credit links serve the hero and expanded detail layouts. Explicit
/// horizontal links keep every director reachable without changing Play's
/// initial-focus priority in the fixed TV composition.
class DetailDirectors extends StatefulWidget {
  final List<Map<String, dynamic>> directors;
  final String serverId;
  final FocusNode? firstFocusNode;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final bool compact;

  const DetailDirectors({
    super.key,
    required this.directors,
    required this.serverId,
    this.firstFocusNode,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.compact = false,
  });
  @override
  State<DetailDirectors> createState() => _DetailDirectorsState();
}

class _DetailDirectorsState extends State<DetailDirectors> {
  final _nodes = <String, FocusNode>{};
  FocusNode _node(String id, bool first) =>
      first && widget.firstFocusNode != null
      ? widget.firstFocusNode!
      : _nodes.putIfAbsent(
          id,
          () => FocusNode(
            debugLabel: 'director:$id',
            skipTraversal: widget.compact,
          ),
        );
  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final people = widget.directors
        .where((p) => (p['Name']?.toString().trim() ?? '').isNotEmpty)
        .toList();
    if (people.isEmpty) {
      return const SizedBox.shrink();
    }
    final links = people
        .where((p) => (p['Id']?.toString().trim() ?? '').isNotEmpty)
        .toList();
    final nodes = [
      for (var i = 0; i < links.length; i++)
        _node(links[i]['Id'].toString(), i == 0),
    ];
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: widget.compact
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(vertical: 12),
      child: Wrap(
        spacing: widget.compact ? 6 : 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            people.length == 1 ? l10n.director : l10n.directors,
            style: Tv26Style.text(
              widget.compact ? 14 : 16,
              color: widget.compact
                  ? Tv26Style.detailHeroSecondary
                  : Tv26Style.secondary,
            ),
          ),
          for (final person in people)
            Builder(
              builder: (context) {
                final name = person['Name'].toString().trim();
                final index = links.indexOf(person);
                if (index < 0) {
                  return Text(
                    name,
                    style: Tv26Style.text(widget.compact ? 14 : 16),
                  );
                }
                return Focus(
                  canRequestFocus: false,
                  onKeyEvent: (_, event) {
                    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                      return KeyEventResult.ignored;
                    }
                    switch (event.logicalKey) {
                      case LogicalKeyboardKey.arrowUp:
                        if (widget.onNavigateUp == null) {
                          return KeyEventResult.ignored;
                        }
                        widget.onNavigateUp!();
                        return KeyEventResult.handled;
                      case LogicalKeyboardKey.arrowDown:
                        if (widget.onNavigateDown == null) {
                          return KeyEventResult.ignored;
                        }
                        widget.onNavigateDown!();
                        return KeyEventResult.handled;
                      case LogicalKeyboardKey.arrowLeft:
                        if (index > 0) {
                          nodes[index - 1].requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (widget.onNavigateLeft != null) {
                          widget.onNavigateLeft!();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      case LogicalKeyboardKey.arrowRight:
                        if (index + 1 < nodes.length) {
                          nodes[index + 1].requestFocus();
                          return KeyEventResult.handled;
                        }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Tv26Button(
                    label: name,
                    focusNode: nodes[index],
                    transparent: true,
                    height: Tv26Style.compactButtonHeight,
                    horizontalPadding: Tv26Style.compactButtonPadding,
                    fontSize: widget.compact ? 14 : 16,
                    onPressed: () => context.push(
                      Destinations.item(
                        person['Id'].toString(),
                        serverId: widget.serverId,
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
