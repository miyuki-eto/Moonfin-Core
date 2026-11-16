/// Labels describe stream capabilities rather than merely copying the badge
/// from a reference image. Unknown dimensions do not imply HD.
String? videoResolutionBadge(Iterable<Map<String, dynamic>> streams) {
  final video = streams
      .where((stream) => stream['Type'] == 'Video')
      .firstOrNull;
  final width = video?['Width'];
  if (width is! num || width <= 0) {
    return null;
  }
  if (width >= 7600) {
    return '8K';
  }
  if (width >= 3800) {
    return '4K';
  }
  if (width >= 1200) {
    return 'HD';
  }
  return 'SD';
}

bool hasClosedCaptions(Iterable<Map<String, dynamic>> streams) => streams.any(
  (stream) =>
      stream['Type'] == 'Subtitle' &&
      (stream['IsHearingImpaired'] == true ||
          stream['IsClosedCaption'] == true ||
          const {
            'eia_608',
            'eia_708',
            'cea608',
            'cea708',
          }.contains(stream['Codec']?.toString().toLowerCase())),
);
