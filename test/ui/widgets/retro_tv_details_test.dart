import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/ui/screens/playback/retro_tv_details.dart';
import 'package:server_core/server_core.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:moonfin/ui/screens/playback/retro_tv_actions.dart';
import 'package:moonfin/ui/screens/playback/retro_tv_dial.dart';
import 'package:moonfin/ui/tv/tv26_button.dart';

class _Items extends Fake implements ItemsApi {
  final responses = <String, Completer<Map<String, dynamic>>>{};
  final requested = <String>[];

  @override
  Future<Map<String, dynamic>> getItem(
    String id, {
    String? mediaSourceId,
    String? fields,
  }) {
    requested.add(id);
    return responses.putIfAbsent(id, Completer.new).future;
  }
}

class _Client extends Fake implements MediaServerClient {
  @override
  final _Items itemsApi = _Items();
}

AggregatedItem _item(String id, {bool episode = false}) => AggregatedItem(
  id: id,
  serverId: 'server',
  rawData: {
    'Name': id,
    'Type': episode ? 'Episode' : 'Movie',
    if (episode) ...{
      'SeriesName': 'The Series',
      'SeriesId': 'series',
      'ParentIndexNumber': 2,
      'IndexNumber': 3,
    },
  },
);

Future<void> _mount(
  WidgetTester tester,
  _Client client,
  AggregatedItem item, {
  double width = 720,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: 320,
          child: RetroTvDetails(item: item, client: client),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'a delayed response fades in without moving the menu or action focus',
    (tester) async {
      final client = _Client();
      final item = _item('Movie');
      item.rawData['RunTimeTicks'] =
          const Duration(minutes: 90).inMicroseconds * 10;
      final programme = RetroProgram(item, DateTime.utc(2026));
      tester.view.physicalSize = const Size(1152, 648);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: RetroTvActionMenu(
                program: programme,
                onDismiss: () {},
                onAction: (_) {},
                details: RetroTvDetails(item: item, client: client),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final info = tester
          .widget<Tv26Button>(find.byType(Tv26Button).first)
          .focusNode!;
      info.requestFocus();
      await tester.pump(const Duration(seconds: 3));
      final card = tester.getRect(find.byType(RetroTvActionMenu));
      final actions = find
          .byType(Tv26Button)
          .evaluate()
          .map((element) => tester.getRect(find.byWidget(element.widget)))
          .toList();
      expect(find.textContaining('Unavailable'), findsNothing);
      expect(find.byType(LoadingThrobber), findsNWidgets(2));
      client.itemsApi.responses['Movie']!.complete({
        'Overview': 'Loaded synopsis',
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final fade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.text('Loaded synopsis'),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, allOf(greaterThan(0), lessThan(1)));
      expect(find.byType(LoadingThrobber), findsOneWidget);
      expect(info.hasFocus, isTrue);
      expect(tester.getRect(find.byType(RetroTvActionMenu)), card);
      await tester.pumpAndSettle();
      expect(find.byType(LoadingThrobber), findsNothing);
      expect(info.hasFocus, isTrue);
      for (var i = 0; i < actions.length; i++) {
        expect(tester.getRect(find.byType(Tv26Button).at(i)), actions[i]);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('full movie metadata fits and uses shared ratings', (
    tester,
  ) async {
    final client = _Client();
    await _mount(tester, client, _item('Movie'));
    client.itemsApi.responses['Movie']!.complete({
      'Overview': 'A complete synopsis describing the movie.',
      'ProductionYear': 1992,
      'CommunityRating': 8.4,
      'People': [
        {'Type': 'Director', 'Name': 'The Director'},
        {'Type': 'Actor', 'Name': 'First Actor'},
        {'Type': 'Actor', 'Name': 'Second Actor'},
      ],
    });
    await tester.pumpAndSettle();
    expect(
      find.text('A complete synopsis describing the movie.'),
      findsOneWidget,
    );
    expect(find.text('Director  The Director'), findsOneWidget);
    expect(find.text('Cast  First Actor, Second Actor'), findsOneWidget);
    expect(find.text('8.4'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(client.itemsApi.requested, ['Movie']);
  });

  testWidgets(
    'episode details include series cast without replacing episode synopsis',
    (tester) async {
      final client = _Client();
      await _mount(tester, client, _item('Episode', episode: true), width: 392);
      client.itemsApi.responses['Episode']!.complete({
        'Overview': 'The episode synopsis.',
        'People': [
          {'Type': 'Director', 'Name': 'Episode Director'},
        ],
      });
      await tester.pump();
      client.itemsApi.responses['series']!.complete({
        'Overview': 'The series synopsis.',
        'People': [
          {'Type': 'Actor', 'Name': 'Series Actor'},
        ],
      });
      await tester.pumpAndSettle();
      expect(find.text('The Series'), findsOneWidget);
      expect(find.text('S02E03 · Episode'), findsOneWidget);
      expect(find.text('The episode synopsis.'), findsOneWidget);
      expect(find.text('The series synopsis.'), findsNothing);
      expect(find.text('Cast  Series Actor'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late metadata cannot replace the next programme', (
    tester,
  ) async {
    final client = _Client();
    await _mount(tester, client, _item('First'));
    await _mount(tester, client, _item('Second'));
    client.itemsApi.responses['Second']!.complete({
      'Overview': 'Second synopsis',
    });
    await tester.pumpAndSettle();
    client.itemsApi.responses['First']!.complete({
      'Overview': 'Stale synopsis',
    });
    await tester.pumpAndSettle();
    expect(find.text('Second synopsis'), findsOneWidget);
    expect(find.text('Stale synopsis'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('a metadata error is shown inside the card', (tester) async {
    final client = _Client();
    await _mount(tester, client, _item('Movie'));
    client.itemsApi.responses['Movie']!.completeError(StateError('Offline'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Full details couldn’t be loaded.'),
      findsOneWidget,
    );
    expect(find.text('Director  Unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
