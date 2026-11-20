"""Builds the offline dictionary (assets/dictionary/wordnet.txt.gz) from
Princeton WordNet 3.1.

    curl -LO https://wordnetcode.princeton.edu/wn3.1.dict.tar.gz
    tar xzf wn3.1.dict.tar.gz
    python3 tool/build_dictionary.py dict assets/dictionary/wordnet.txt.gz

The output is plain text, gzipped, in three sections split by "%%" lines:

1. Glosses, one per line: "<pos>\t<gloss>". Line n is gloss number n.
   pos is n (noun), v (verb), a (adjective) or r (adverb).
2. Words: "<word>\t<gloss numbers, most common sense first>". Words are
   lowercase with spaces, as WordNet writes them with underscores.
3. Irregular forms: "<pos>\t<form>\t<base forms>", e.g. "v\tran\trun".
"""

import gzip
import os
import sys

POS = {"noun": "n", "verb": "v", "adj": "a", "adv": "r"}


def main(src: str, out: str) -> None:
    glosses: list[str] = []
    ids: dict[tuple[str, int], int] = {}
    for name, pos in POS.items():
        with open(os.path.join(src, f"data.{name}"), encoding="utf-8") as f:
            for line in f:
                if line.startswith("  "):  # License header.
                    continue
                offset = int(line[:8])
                gloss = line.split(" | ", 1)[1].strip() if " | " in line else ""
                ids[(pos, offset)] = len(glosses)
                glosses.append(f"{pos}\t{gloss}")

    words: dict[str, list[int]] = {}
    for name, pos in POS.items():
        with open(os.path.join(src, f"index.{name}"), encoding="utf-8") as f:
            for line in f:
                if line.startswith("  "):
                    continue
                parts = line.split()
                lemma = parts[0].replace("_", " ")
                pointers = int(parts[3])
                # lemma pos synset_cnt p_cnt [ptr...] sense_cnt tagsense_cnt offsets
                offsets = parts[4 + pointers + 2 :]
                senses = words.setdefault(lemma, [])
                senses += [ids[(pos, int(o))] for o in offsets]

    forms: list[str] = []
    for name, pos in POS.items():
        with open(os.path.join(src, f"{name}.exc"), encoding="utf-8") as f:
            for line in f:
                form, *bases = line.split()
                forms.append(
                    f"{pos}\t{form.replace('_', ' ')}\t"
                    + ",".join(b.replace("_", " ") for b in bases)
                )

    lines = (
        glosses
        + ["%%"]
        + [f"{w}\t{','.join(map(str, s))}" for w, s in sorted(words.items())]
        + ["%%"]
        + forms
    )
    with gzip.open(out, "wt", encoding="utf-8", compresslevel=9) as f:
        f.write("\n".join(lines) + "\n")
    print(f"{len(glosses)} glosses, {len(words)} words, {len(forms)} forms")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
