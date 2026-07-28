import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_system/services/frog_service.dart';

void main() {
  group('dayKeyFor', () {
    test('a moment just before 4am belongs to the previous calendar day', () {
      final now = DateTime(2026, 7, 27, 3, 59);
      expect(dayKeyFor(now), '2026-07-26');
    });

    test('4am exactly already belongs to the new day', () {
      final now = DateTime(2026, 7, 27, 4, 0);
      expect(dayKeyFor(now), '2026-07-27');
    });

    test('midday is unaffected by the shift', () {
      final now = DateTime(2026, 7, 27, 13, 0);
      expect(dayKeyFor(now), '2026-07-27');
    });
  });

  group('pickFrog', () {
    test('excludes the given filename when another candidate exists', () {
      final pool = [
        const MapEntry('a.json', {'title': 'A'}),
        const MapEntry('b.json', {'title': 'B'}),
      ];
      // A fixed seed makes Random() picks deterministic for this pool size.
      for (var seed = 0; seed < 20; seed++) {
        final picked = pickFrog(pool, excludeFilename: 'a.json', random: Random(seed));
        expect(picked.key, 'b.json');
      }
    });

    test('falls back to the full pool when excluding would leave nothing', () {
      final pool = [const MapEntry('only.json', {'title': 'Only'})];
      final picked = pickFrog(pool, excludeFilename: 'only.json', random: Random(0));
      expect(picked.key, 'only.json');
    });

    test('picks from the full pool when no exclusion is given', () {
      final pool = [const MapEntry('solo.json', {'title': 'Solo'})];
      final picked = pickFrog(pool, random: Random(0));
      expect(picked.key, 'solo.json');
    });
  });
}
