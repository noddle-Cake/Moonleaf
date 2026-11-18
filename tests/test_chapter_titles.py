import pytest

from services.chapter_titles import clean_chapter_title

BOOK = 'The Lantern Keeper'


@pytest.mark.parametrize('raw, expected', [
    ('The Lantern Keeper Chapter 1', 'Chapter 1'),
    ('The Lantern Keeper - Chapter 2: Salt and Lamplight', 'Chapter 2: Salt and Lamplight'),
    ('Chapter 3 - The Lantern Keeper', 'Chapter 3'),
    ('the lantern keeper | Chapter 4 – Night Ferry', 'Chapter 4: Night Ferry'),
    ('Chapter 12 - The Fall', 'Chapter 12: The Fall'),
    ('Ch. 7: Driftwood Crowns', 'Chapter 7: Driftwood Crowns'),
    ('ch 8 Under the Seawall', 'Chapter 8: Under the Seawall'),
    ('12. The Fall', 'Chapter 12: The Fall'),
    ('#13 - Morning', 'Chapter 13: Morning'),
    ('Chapter 5.5: Interlude', 'Chapter 5.5: Interlude'),
    ('Episode 9 — Choir', 'Chapter 9: Choir'),
    ('Chapter 10: Chapter 10', 'Chapter 10'),
    ('Prologue', 'Chapter 1: Prologue'),
    ('', 'Chapter 1'),
    ('The Lantern Keeper', 'Chapter 1'),
])
def test_chapter_names(raw, expected):
    assert clean_chapter_title(raw, BOOK, 1) == expected


def test_numbers_inside_names_and_short_titles():
    assert clean_chapter_title('2019 Was a Long Year', 'Other Book', 4) == 'Chapter 4: 2019 Was a Long Year'
    assert clean_chapter_title('Chapter 3: 1000 Lanterns', 'Book', 3) == 'Chapter 3: 1000 Lanterns'
    assert clean_chapter_title('Chapter 2: An Ox', 'Ox', 2) == 'Chapter 2: An Ox'
