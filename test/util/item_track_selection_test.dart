import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/util/item_track_selection.dart';

void main() {
  const english = <String, dynamic>{
    'Type': 'Subtitle',
    'Index': 3,
    'Language': 'eng',
    'Codec': 'PGSSUB',
    'IsDefault': true,
  };
  const german = <String, dynamic>{
    'Type': 'Subtitle',
    'Index': 4,
    'Language': 'ger',
    'Codec': 'PGSSUB',
  };
  test('adding an external caption cannot reuse an old numeric index', () {
    final saved = itemTrackSelection([english, german], 3);
    final shifted = [
      {
        'Type': 'Subtitle',
        'Index': 0,
        'Language': 'kor',
        'Codec': 'subrip',
        'IsExternal': true,
      },
      {...english, 'Index': 4},
      {...german, 'Index': 5},
    ];
    expect(restoreItemTrackSelection(saved, shifted), 4);
  });
  test(
    'corrected swapped language labels follow English rather than index',
    () {
      final saved = itemTrackSelection([english, german], 3);
      expect(
        restoreItemTrackSelection(saved, [
          {...english, 'Language': 'deu', 'IsDefault': false},
          {...german, 'Language': 'eng', 'IsDefault': true},
        ]),
        4,
      );
    },
  );
  test('audio identity distinguishes main dialogue from commentary', () {
    const main = {
      'Type': 'Audio',
      'Index': 1,
      'Language': 'jpn',
      'Codec': 'aac',
      'Channels': 6,
    };
    final saved = itemTrackSelection([main], 1);
    expect(
      restoreItemTrackSelection(saved, [
        {...main, 'Language': 'eng'},
        {...main, 'Index': 2},
        {...main, 'Index': 3, 'Title': 'Commentary', 'IsCommentary': true},
      ]),
      2,
    );
  });
  test('missing or ambiguous tracks return to configured defaults', () {
    final saved = itemTrackSelection([english], 3);
    expect(restoreItemTrackSelection(saved, [german]), isNull);
    expect(
      restoreItemTrackSelection(saved, [
        english,
        {...english, 'Index': 6},
      ]),
      isNull,
    );
    expect(restoreItemTrackSelection({'index': 3}, [german]), isNull);
  });
  test('explicit off survives a changed stream list', () {
    expect(
      restoreItemTrackSelection(itemTrackSelection([english], -1), [german]),
      -1,
    );
    expect(itemTrackSelection([english], null), isNull);
    expect(itemTrackSelection([english], 99), isNull);
  });
  test(
    'full, forced, external and SDH captions remain different identities',
    () {
      final saved = itemTrackSelection([english], 3);
      for (final key in ['IsForced', 'IsExternal', 'IsHearingImpaired']) {
        expect(
          restoreItemTrackSelection(saved, [
            {...english, key: true},
          ]),
          isNull,
        );
      }
    },
  );
}
