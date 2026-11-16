import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/detail/video_metadata.dart';

void main() {
  test('source dimensions distinguish unknown, SD, HD, UHD and 8K', () {
    expect(videoResolutionBadge([]), isNull);
    for (final (width, badge) in [
      (720, 'SD'),
      (1280, 'HD'),
      (1920, 'HD'),
      (3840, '4K'),
      (7680, '8K'),
    ]) {
      expect(
        videoResolutionBadge([
          {'Type': 'Video', 'Width': width},
        ]),
        badge,
      );
    }
  });
  test('ordinary subtitles do not claim closed-caption support', () {
    expect(
      hasClosedCaptions([
        {'Type': 'Subtitle', 'Codec': 'subrip'},
      ]),
      isFalse,
    );
    expect(
      hasClosedCaptions([
        {'Type': 'Subtitle', 'IsHearingImpaired': true},
      ]),
      isTrue,
    );
    expect(
      hasClosedCaptions([
        {'Type': 'Subtitle', 'Codec': 'eia_608'},
      ]),
      isTrue,
    );
    expect(
      hasClosedCaptions([
        {'Type': 'Audio', 'IsHearingImpaired': true},
      ]),
      isFalse,
    );
  });
}
