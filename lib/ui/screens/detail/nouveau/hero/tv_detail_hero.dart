import 'package:flutter/material.dart';

import '../../../../tv/tv26_button.dart';

import 'package:flutter/services.dart';

import '../../../../../data/models/aggregated_item.dart';
import '../../../../widgets/navigation_layout.dart';
import '../../../../tv/tv26_classification.dart';
import '../../../../tv/tv26_style.dart';
import '../../../../tv/tv_text_dialog.dart';
import '../../detail_directors.dart';
import '../../video_metadata.dart';
import '../../../../../l10n/app_localizations.dart';

/// Both loaded content and the skeleton use the reference's action baseline.
class TvDetailHeroFrame extends StatelessWidget {
  final Widget child;

  const TvDetailHeroFrame({super.key, required this.child});

  static double heightForWidth(double width) => 580 * width / 1145;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.sizeOf(context).width / 1145;
    return SizedBox(
      height: heightForWidth(MediaQuery.sizeOf(context).width),
      child: Padding(
        padding: EdgeInsets.fromLTRB(48 * scale, 0, 48 * scale, 10 * scale),
        child: FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.bottomLeft,
          child: SizedBox(
            width: 1049,
            height: 570,
            child: Align(alignment: Alignment.bottomLeft, child: child),
          ),
        ),
      ),
    );
  }
}

/// Apple TV's title page is a fixed composition over full-bleed artwork.
/// Credits occupy the right column; the synopsis and compact metadata sit left.
class TvDetailHero extends StatelessWidget {
  final AggregatedItem item;
  final List<Map<String, dynamic>> streams;
  final Widget branding;
  final Widget actions;
  final String overview;
  final List<Map<String, dynamic>> actors;
  final List<Map<String, dynamic>> directors;
  final FocusNode directorFocusNode;
  final FocusNode? overviewFocusNode;
  final VoidCallback onDirectorDown;

  const TvDetailHero({
    super.key,
    required this.item,
    required this.branding,
    required this.streams,
    required this.actions,
    required this.overview,
    required this.actors,
    required this.directors,
    required this.directorFocusNode,
    this.overviewFocusNode,
    required this.onDirectorDown,
  });

  Widget _badge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    decoration: BoxDecoration(
      color: Tv26Style.foreground.withValues(alpha: .8),
      borderRadius: BorderRadius.circular(1),
    ),
    child: Text(
      text,
      style: Tv26Style.text(
        9,
        color: const Color(0xFF333333),
        weight: FontWeight.w700,
        height: 1.2,
      ),
    ),
  );

  Widget _metadata(BuildContext context) {
    final runtime = item.runtime;
    final minutes = runtime?.inMinutes;
    final runtimeText = minutes == null || minutes <= 0
        ? null
        : AppLocalizations.of(context).durationMinutes(minutes);
    final resolution = videoResolutionBadge(streams);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          [
            if (item.productionYear != null) '${item.productionYear}',
            ?runtimeText,
          ].join(' · '),
          style: Tv26Style.text(14),
        ),
        if (item.criticRating != null) ...[
          const SizedBox(width: 5),
          Image.asset(
            'assets/icons/ratings/${item.criticRating! >= 60 ? 'rt-fresh' : 'rt-rotten'}.png',
            width: 13,
            height: 13,
          ),
          Text('${item.criticRating}%', style: Tv26Style.text(14)),
        ],
        if (resolution != null) ...[
          const SizedBox(width: 8),
          _badge(resolution),
        ],
        if (item.hdrType?.isNotEmpty ?? false) ...[
          const SizedBox(width: 5),
          _badge(item.hdrType!),
        ],
        if (hasClosedCaptions(streams)) ...[
          const SizedBox(width: 5),
          _badge('CC'),
        ],
      ],
    );
  }

  Widget _credits(BuildContext context) {
    final starring = actors
        .map((p) => p['Name']?.toString() ?? '')
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .take(3)
        .join(', ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (starring.isNotEmpty)
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${AppLocalizations.of(context).starring} ',
                  style: Tv26Style.text(
                    14,
                    color: Tv26Style.detailHeroSecondary,
                  ),
                ),
                TextSpan(text: starring, style: Tv26Style.text(14)),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        DetailDirectors(
          directors: directors,
          serverId: item.serverId,
          firstFocusNode: directorFocusNode,
          compact: true,
          onNavigateUp: () => NavigationLayout.focusNavbar(),
          onNavigateDown: onDirectorDown,
          onNavigateLeft: overviewFocusNode?.requestFocus,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 570,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          bottom: 0,
          width: 510,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: item.type == 'Season' ? 410 : 210,
                height: 76,
                child: Align(alignment: Alignment.bottomLeft, child: branding),
              ),
              const SizedBox(height: Tv26Style.heroActionGap),
              Tv26Classification(
                isMovie: item.type == 'Movie',
                type: switch ((
                  item.type,
                  item.parentIndexNumber,
                  item.indexNumber,
                )) {
                  ('Movie', _, _) => AppLocalizations.of(context).movie,
                  ('Episode', final season?, final episode?) =>
                    'S$season:E$episode · ${item.name}',
                  ('Episode', _, _) => item.name,
                  ('BoxSet', _, _) => AppLocalizations.of(context).collection,
                  ('Season', _, _) => AppLocalizations.of(context).season,
                  ('Video', _, _) => AppLocalizations.of(context).video,
                  ('Trailer', _, _) => AppLocalizations.of(context).trailer,
                  ('Series', _, _) => AppLocalizations.of(context).series,
                  _ => item.type ?? '',
                },
                genres: item.genres,
                rating: item.officialRating,
              ),
              if (overview.isNotEmpty) ...[
                const SizedBox(height: Tv26Style.gap),
                SizedBox(
                  width: 410,
                  child: Text(
                    overview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Tv26Style.text(
                      14,
                      color: Tv26Style.detailHeroSecondary,
                      height: 1.25,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: (_, event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      NavigationLayout.focusNavbar();
                      return KeyEventResult.handled;
                    }
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      onDirectorDown();
                      return KeyEventResult.handled;
                    }
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.arrowRight) {
                      if (directorFocusNode.context?.mounted == true) {
                        directorFocusNode.requestFocus();
                      } else {
                        onDirectorDown();
                      }
                      return KeyEventResult.handled;
                    }
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      NavigationLayout.focusNavbar();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Tv26Button(
                    label: AppLocalizations.of(context).readMore,
                    focusNode: overviewFocusNode,
                    transparent: true,
                    height: Tv26Style.compactButtonHeight,
                    horizontalPadding: Tv26Style.compactButtonPadding,
                    fontSize: 13,
                    onPressed: () => showTvTextDialog(
                      context,
                      title: item.name,
                      text: overview,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: Tv26Style.gap),
              _metadata(context),
              const SizedBox(height: Tv26Style.heroActionGap),
              Transform.translate(offset: const Offset(-3, 0), child: actions),
            ],
          ),
        ),
        Positioned(left: 804, right: 0, bottom: 0, child: _credits(context)),
      ],
    ),
  );
}
