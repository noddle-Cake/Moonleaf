import 'package:flutter_test/flutter_test.dart';
import 'package:novel_to_epub/data/chapter_titles.dart';

void main() {
  test('chapter names become "Chapter N: Name"', () {
    const book = 'The Lantern Keeper';
    final cases = {
      // Site repeats the book title in the heading.
      'The Lantern Keeper Chapter 1': 'Chapter 1',
      'The Lantern Keeper - Chapter 2: Salt and Lamplight':
          'Chapter 2: Salt and Lamplight',
      'Chapter 3 - The Lantern Keeper': 'Chapter 3',
      'the lantern keeper | Chapter 4 – Night Ferry': 'Chapter 4: Night Ferry',
      // Site numbering in different styles.
      'Chapter 12 - The Fall': 'Chapter 12: The Fall',
      'Ch. 7: Driftwood Crowns': 'Chapter 7: Driftwood Crowns',
      'ch 8 Under the Seawall': 'Chapter 8: Under the Seawall',
      '12. The Fall': 'Chapter 12: The Fall',
      '#13 - Morning': 'Chapter 13: Morning',
      'Chapter 5.5: Interlude': 'Chapter 5.5: Interlude',
      'Episode 9 — Choir': 'Chapter 9: Choir',
      'Chapter 10: Chapter 10': 'Chapter 10',
      // No number: use the position.
      'Prologue': 'Chapter 1: Prologue',
      '': 'Chapter 1',
      'The Lantern Keeper': 'Chapter 1',
    };
    for (final MapEntry(key: raw, value: expected) in cases.entries) {
      expect(cleanChapterTitle(raw, book, 1), expected, reason: raw);
    }
  });

  test('numbers inside names are left alone', () {
    expect(
      cleanChapterTitle('2019 Was a Long Year', 'Other Book', 4),
      'Chapter 4: 2019 Was a Long Year',
    );
    expect(
      cleanChapterTitle('Chapter 3: 1000 Lanterns', 'Book', 3),
      'Chapter 3: 1000 Lanterns',
    );
  });

  test('a short or missing book title is not stripped', () {
    expect(cleanChapterTitle('Chapter 2: An Ox', 'Ox', 2), 'Chapter 2: An Ox');
    expect(cleanChapterTitle('Chapter 2: Start', '', 2), 'Chapter 2: Start');
  });
}
