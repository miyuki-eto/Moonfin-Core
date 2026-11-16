import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/utils/people_credits.dart';

void main() {
  test('repeated character credits become one person without losing roles or artwork', () {
    final people = mergePeopleCredits([
      {'Id': 'a', 'Name': 'Actor', 'Role': 'One', 'PrimaryImageTag': 'art'},
      {'Id': 'b', 'Name': 'Someone else', 'Role': 'Three'},
      {'Id': 'a', 'Name': 'Actor', 'Role': 'Two'},
      {'Id': 'a', 'Name': 'Actor', 'Role': 'One'},
    ]);
    expect(people.map((p) => p['Id']), ['a', 'b']);
    expect(people.first['Role'], 'One / Two');
    expect(people.first['PrimaryImageTag'], 'art');
  });
  test('different people with the same name keep separate identities', () {
    expect(
      mergePeopleCredits([
        {'Id': 'a', 'Name': 'Actor'},
        {'Id': 'b', 'Name': 'Actor'},
        {'Name': 'No ID', 'Role': 'One'},
        {'Name': 'No ID', 'Role': 'Two'},
        {},
      ]),
      hasLength(3),
    );
  });
}
