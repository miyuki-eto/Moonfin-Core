import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../data/models/aggregated_item.dart';
import '../../widgets/bounded_network_image.dart';
import '../../widgets/rating_display.dart';
import '../../tv/tv_reveal_transition.dart';

/// Loads the current programme's full metadata without touching playback.
class RetroTvDetails extends StatefulWidget {
  const RetroTvDetails({super.key, required this.item, required this.client});

  final AggregatedItem item;
  final MediaServerClient client;

  @override
  State<RetroTvDetails> createState() => _RetroTvDetailsState();
}

class _RetroTvDetailsState extends State<RetroTvDetails> {
  late Future<AggregatedItem> _details = _loadDetails();

  @override
  void didUpdateWidget(RetroTvDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.serverId != widget.item.serverId ||
        oldWidget.client != widget.client) {
      _details = _loadDetails();
    }
  }

  Future<AggregatedItem> _loadDetails() async {
    final item = widget.item;
    final client = widget.client;
    final full = await client.itemsApi.getItem(item.id);
    final details = AggregatedItem(
      id: item.id,
      serverId: item.serverId,
      rawData: {...item.rawData, ...full},
    );
    if (details.type == 'Episode' &&
        details.seriesId != null &&
        !details.people.any((person) => person['Type'] == 'Actor')) {
      final series = await client.itemsApi.getItem(details.seriesId!);
      final seriesItem = AggregatedItem(
        id: details.seriesId!,
        serverId: item.serverId,
        rawData: series,
      );
      return AggregatedItem(
        id: item.id,
        serverId: item.serverId,
        rawData: {
          ...details.rawData,
          'People': [
            ...details.people,
            ...seriesItem.people.where((person) => person['Type'] == 'Actor'),
          ],
        },
      );
    }
    return details;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AggregatedItem>(
    key: ValueKey((widget.item.serverId, widget.item.id)),
    future: _details,
    initialData: widget.item,
    builder: (context, snapshot) {
      final item = snapshot.data ?? widget.item;
      final episode = item.type == 'Episode';
      final posterId = episode ? item.seriesId ?? item.id : item.id;
      final posterTag = episode
          ? item.seriesPrimaryImageTag
          : item.primaryImageTag;
      final directors = item.people
          .where((person) => person['Type'] == 'Director')
          .map((person) => person['Name'])
          .whereType<String>()
          .toSet()
          .join(', ');
      final cast = item.people
          .where(
            (person) =>
                person['Type'] == 'Actor' || person['Type'] == 'GuestStar',
          )
          .map((person) => person['Name'])
          .whereType<String>()
          .toSet()
          .join(', ');
      final metadata = [
        if (item.productionYear != null) item.productionYear.toString(),
        if (item.runtime != null) '${item.runtime!.inMinutes} min',
        ...item.genres.take(2),
        if (item.officialRating?.isNotEmpty ?? false) item.officialRating!,
      ].join(' · ');
      final title = episode && (item.seriesName?.isNotEmpty ?? false)
          ? item.seriesName!
          : item.name;
      final episodeLabel = [
        if (item.parentIndexNumber != null)
          'S${item.parentIndexNumber.toString().padLeft(2, '0')}',
        if (item.indexNumber != null)
          'E${item.indexNumber.toString().padLeft(2, '0')}',
      ].join();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 144,
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Tv26Style.radius),
                child: posterTag == null
                    ? ColoredBox(
                        color: Tv26Style.surface,
                        child:
                            snapshot.connectionState == ConnectionState.waiting
                            ? const Center(
                                child: LoadingThrobber(
                                  color: Colors.white,
                                  semanticsLabel: 'Loading poster',
                                ),
                              )
                            : const Icon(
                                Icons.movie_outlined,
                                color: Tv26Style.secondary,
                              ),
                      )
                    : BoundedNetworkImage(
                        fadeInDuration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : AppMotion.screen,
                        placeholderBuilder: (_, _) => const ColoredBox(
                          color: Tv26Style.surface,
                          child: Center(
                            child: LoadingThrobber(
                              color: Colors.white,
                              semanticsLabel: 'Loading poster',
                            ),
                          ),
                        ),
                        imageUrl: widget.client.imageApi.getPrimaryImageUrl(
                          posterId,
                          maxWidth: 320,
                          tag: posterTag,
                        ),
                        maxWidth: 320,
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: Tv26Style.surface,
                          child: Icon(
                            Icons.movie_outlined,
                            color: Tv26Style.secondary,
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: Tv26Style.detailHeaderGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Tv26Style.text(21, weight: FontWeight.w700),
                ),
                if (episode)
                  Text(
                    [
                      if (episodeLabel.isNotEmpty) episodeLabel,
                      item.name,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tv26Style.text(14, color: Tv26Style.secondary),
                  ),
                const SizedBox(height: Tv26Style.gap / 2),
                Text(
                  metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tv26Style.text(14, color: Tv26Style.secondary),
                ),
                if (item.communityRating != null ||
                    item.criticRating != null) ...[
                  const SizedBox(height: Tv26Style.gap / 2),
                  SizedBox(
                    height: 26,
                    child: RatingsRow(
                      ratings: const {},
                      communityRating: item.communityRating,
                      criticRating: item.criticRating,
                      showLabels: false,
                      showBadges: false,
                      singleLine: true,
                    ),
                  ),
                ],
                const SizedBox(height: Tv26Style.gap),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : AppMotion.screen,
                    switchInCurve: TvRevealTransition.curve,
                    switchOutCurve: TvRevealTransition.curve,
                    layoutBuilder: (current, previous) => Stack(
                      fit: StackFit.expand,
                      alignment: Alignment.topLeft,
                      children: [...previous, ?current],
                    ),
                    transitionBuilder: (child, animation) =>
                        TvRevealTransition(animation: animation, child: child),
                    child: snapshot.connectionState == ConnectionState.waiting
                        ? const Center(
                            key: ValueKey('loading-details'),
                            child: LoadingThrobber(
                              color: Colors.white,
                              semanticsLabel: 'Loading programme details',
                            ),
                          )
                        : Column(
                            key: const ValueKey('loaded-details'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.topLeft,
                                  child: Text(
                                    snapshot.hasError
                                        ? 'Full details couldn’t be loaded. Close and reopen Info to retry.'
                                        : item.overview?.trim().isNotEmpty ==
                                              true
                                        ? item.overview!.trim()
                                        : 'Synopsis unavailable.',
                                    maxLines: 6,
                                    overflow: TextOverflow.ellipsis,
                                    style: Tv26Style.text(
                                      15,
                                      color: Tv26Style.detailHeroSecondary,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: Tv26Style.gap / 2),
                              Text(
                                'Director  ${directors.isEmpty ? 'Unavailable' : directors}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Tv26Style.text(14),
                              ),
                              const SizedBox(height: Tv26Style.gap / 3),
                              Text(
                                'Cast  ${cast.isEmpty ? 'Unavailable' : cast}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Tv26Style.text(
                                  14,
                                  color: Tv26Style.detailHeroSecondary,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
