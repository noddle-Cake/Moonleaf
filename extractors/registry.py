from urllib.parse import urlsplit

from .base import BaseExtractor
from .official import Ao3Extractor, StandardEbooksExtractor
from .royalRoad import RoyalRoadExtractor
from .roliascan import RoliaScanExtractor
from .indra import IndraExtractor

EXTRACTORS: list[type[BaseExtractor]] = [RoyalRoadExtractor, RoliaScanExtractor, Ao3Extractor,
                                         StandardEbooksExtractor, IndraExtractor]

# These sites ask every visitor to pass a human check, which only the Moonleaf
# app's built-in browser can show; a server can't download them.
BROWSER_ONLY = {"scribblehub.com": "Scribble Hub", "fanfiction.net": "FanFiction.net",
                "fictionpress.com": "FictionPress"}


def get_extractor(url: str, **kwargs) -> BaseExtractor:
    for extractor_cls in EXTRACTORS:
        if extractor_cls.supports(url):
            return extractor_cls(**kwargs)
    host = (urlsplit(url).hostname or "").removeprefix("www.").removeprefix("m.")
    if host in BROWSER_ONLY and urlsplit(url).scheme in {"http", "https"}:
        raise ValueError(f"{BROWSER_ONLY[host]} asks visitors to confirm they're human, so it works only "
                         "in the Moonleaf app for Android, iOS or macOS.")
    raise ValueError(f"No extractor found for URL: {url}")
