from typing import NotRequired, TypedDict


class BookMetadata(TypedDict):
    title: str | None
    author: str | None
    cover_url: str | None
    chapter_1: str | None
    description: str | None
    # The novel's main page; detection from a chapter link fills this in.
    url: NotRequired[str]
