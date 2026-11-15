import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import 'retro_tv_dial.dart';

enum RetroTvAction { details, watch, startOver, previous }

String retroChannelLabel(RetroChannel channel) =>
    'CH ${channel.number.toString().padLeft(2, '0')}  ·  ${channel.station.label}';

/// Fixed geometry and concentric padding shared by every Retro TV panel.
class RetroTvSurface extends StatelessWidget {
  const RetroTvSurface({
    super.key,
    required this.height,
    required this.width,
    required this.child,
  });
  final double height;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    alignment: Alignment.bottomLeft,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.normal,
    curve: AppMotion.ease,
    child: LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: height * MediaQuery.textScalerOf(context).scale(1),
        width: constraints.constrainWidth(width),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Tv26Style.scrim,
            borderRadius: BorderRadius.circular(Tv26Style.panelRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Tv26Style.gap),
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// Screen-edge panels share their geometry and fade into the playing picture.
class RetroTvSidePanel extends StatelessWidget {
  const RetroTvSidePanel({
    super.key,
    required this.width,
    required this.child,
    this.left = false,
  });
  final double width;
  final bool left;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final extent = constraints.constrainWidth(width);
      return AnimatedSize(
        alignment: left ? Alignment.centerLeft : Alignment.centerRight,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppMotion.normal,
        curve: AppMotion.ease,
        child: SizedBox(
          width: extent,
          height: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: left ? Alignment.centerLeft : Alignment.centerRight,
                end: left ? Alignment.centerRight : Alignment.centerLeft,
                colors: [
                  Tv26Style.canvas.withValues(alpha: .94),
                  Tv26Style.canvas.withValues(alpha: .86),
                  Tv26Style.canvas.withValues(alpha: 0),
                ],
                stops: [0, (1 - Tv26Style.inset / extent).clamp(0.0, 1.0), 1],
              ),
            ),
            child: child,
          ),
        ),
      );
    },
  );
}

/// Passive information is anchored to a screen edge, fading into the picture.
class RetroTvEdgeBanner extends StatelessWidget {
  const RetroTvEdgeBanner({
    super.key,
    required this.top,
    required this.height,
    required this.child,
  });
  final bool top;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: height * MediaQuery.textScalerOf(context).scale(1),
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: top ? Alignment.topCenter : Alignment.bottomCenter,
          end: top ? Alignment.bottomCenter : Alignment.topCenter,
          colors: [
            Tv26Style.canvas.withValues(alpha: .9),
            Tv26Style.scrim,
            Tv26Style.canvas.withValues(alpha: 0),
          ],
          stops: const [0, .55, 1],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Tv26Style.inset,
          vertical: Tv26Style.sectionGap,
        ),
        child: child,
      ),
    ),
  );
}

/// Channel identity stays above the picture while programme information is below.
class RetroTvChannelBanner extends StatelessWidget {
  const RetroTvChannelBanner({super.key, required this.channel});
  final RetroChannel channel;

  @override
  Widget build(BuildContext context) => RetroTvEdgeBanner(
    top: true,
    height: 132,
    child: Row(
      children: [
        Text(
          channel.number.toString().padLeft(2, '0'),
          style: Tv26Style.text(32, weight: FontWeight.w700),
        ),
        const SizedBox(width: Tv26Style.detailHeaderGap),
        Expanded(
          child: Text(
            channel.station.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Tv26Style.text(21, weight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

/// Schedule feedback has no focusable controls.
class RetroTvBanner extends StatelessWidget {
  const RetroTvBanner({super.key, required this.program, required this.next});
  final RetroProgram program;
  final RetroProgram next;

  @override
  Widget build(BuildContext context) => RetroTvEdgeBanner(
    top: false,
    height: 208,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RetroTvProgramSummary(
          program: program,
          next: next,
          maxWidth: double.infinity,
          compact: true,
        ),
        const SizedBox(height: Tv26Style.gap),
        RetroTvTiming(program: program),
        const Spacer(),
        Text(
          'OK / → Options   ← Channels   ↑ ↓ Change channel',
          style: Tv26Style.text(13, color: Tv26Style.secondary),
        ),
      ],
    ),
  );
}

/// Broadcast progress is based on the schedule, not the player's seek position.
class RetroTvTiming extends StatelessWidget {
  const RetroTvTiming({super.key, required this.program});
  final RetroProgram program;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.timestamp();
    final duration = program.endsAt.difference(program.startsAt).inMilliseconds;
    final progress =
        (now.difference(program.startsAt).inMilliseconds / duration).clamp(
          0.0,
          1.0,
        );
    final remaining = (program.endsAt.difference(now).inSeconds / 60)
        .ceil()
        .clamp(0, 1440);
    String time(DateTime value) =>
        MaterialLocalizations.of(context).formatTimeOfDay(
          TimeOfDay.fromDateTime(value.toLocal()),
          alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
        );
    return Row(
      children: [
        Text(
          '${time(program.startsAt)}–${time(program.endsAt)}',
          style: Tv26Style.text(13, color: Tv26Style.detailHeroSecondary),
        ),
        const SizedBox(width: Tv26Style.gap),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Tv26Style.radius),
            child: ExcludeSemantics(
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 2,
                color: Tv26Style.foreground,
                backgroundColor: Tv26Style.border,
              ),
            ),
          ),
        ),
        const SizedBox(width: Tv26Style.gap),
        Text(
          '$remaining min left',
          style: Tv26Style.text(13, color: Tv26Style.detailHeroSecondary),
        ),
      ],
    );
  }
}

class RetroTvProgramSummary extends StatelessWidget {
  const RetroTvProgramSummary({
    super.key,
    required this.program,
    required this.next,
    this.maxWidth = 540,
    this.compact = false,
  });

  final RetroProgram program;
  final RetroProgram next;
  final double maxWidth;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final nextStart = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(next.startsAt.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final nowListing = RetroTvProgramListing(
      program: program,
      label: 'NOW',
      current: true,
      compact: compact,
    );
    final nextListing = RetroTvProgramListing(
      program: next,
      label: 'NEXT  ·  $nextStart',
      compact: compact,
    );
    const gap = Tv26Style.detailHeaderGap;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: nowListing),
          const SizedBox(width: gap),
          Expanded(child: nextListing),
        ],
      ),
    );
  }
}

/// A single programme uses the same title and episode hierarchy in banners and menus.
class RetroTvProgramListing extends StatelessWidget {
  const RetroTvProgramListing({
    super.key,
    required this.program,
    required this.label,
    this.current = false,
    this.compact = false,
    this.foregroundColor,
  });
  final RetroProgram program;
  final String label;
  final bool current;
  final bool compact;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final item = program.item;
    final series = item.seriesName?.trim();
    final isEpisode = item.type == 'Episode';
    final hasSeries = isEpisode && series != null && series.isNotEmpty;
    final season = item.parentIndexNumber;
    final episode = item.indexNumber;
    final episodeNumber = [
      if (season != null) 'S${season.toString().padLeft(2, '0')}',
      if (episode != null) 'E${episode.toString().padLeft(2, '0')}',
    ].join();
    final metadata = isEpisode
        ? [
            if (episodeNumber.isNotEmpty) episodeNumber,
            if (hasSeries) item.name,
          ].join('\u00a0·\u00a0')
        : [
            if (item.productionYear != null) item.productionYear.toString(),
            if (item.runtime != null) '${item.runtime!.inMinutes} min',
          ].join(' · ');
    final titleStyle = Tv26Style.text(
      21,
      color: foregroundColor ?? Tv26Style.foreground,
      weight: current ? FontWeight.w700 : FontWeight.w600,
    );
    final metadataStyle = Tv26Style.text(
      14,
      color:
          foregroundColor?.withValues(alpha: .72) ??
          Tv26Style.detailHeroSecondary,
    );
    final scaler = MediaQuery.textScalerOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Tv26Style.text(
            13,
            color:
                foregroundColor?.withValues(alpha: .72) ??
                Tv26Style.detailHeroSecondary,
            weight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Tv26Style.gap / 3),
        SizedBox(
          height:
              scaler.scale(titleStyle.fontSize!) *
              titleStyle.height! *
              (compact ? 1 : 2),
          child: Text(
            hasSeries ? series : item.name,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
        ),
        const SizedBox(height: Tv26Style.gap / 3),
        SizedBox(
          height:
              scaler.scale(metadataStyle.fontSize!) *
              metadataStyle.height! *
              (compact ? 1 : 2),
          child: Text(
            metadata,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: metadataStyle,
          ),
        ),
      ],
    );
  }
}
