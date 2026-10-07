#!/usr/bin/env python3
"""Writes translations from a worklist into the String Catalogs.

Usage: apply_translations.py <worklist.json> <translations.json> [language]

translations.json maps worklist numbers to translated text: {"1": "Hola", ...}.
Placeholders (%@, %lld, %1$@ ...) and inflection markup must survive translation;
entries that lose them are rejected and listed.
"""
import collections
import json
import pathlib
import re
import sys

PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:l{0,2}[dfu]|@|lf|%)")


def placeholders(text: str) -> collections.Counter:
    found = collections.Counter(p for p in PLACEHOLDER.findall(text) if p != "%%")
    found["inflect"] = text.count("](inflect: true)")
    return found


def main() -> int:
    worklist = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
    translations = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
    language = sys.argv[3] if len(sys.argv) > 3 else "es"

    catalogs: dict[str, dict] = {}
    rejected, missing, written = [], [], 0
    for item in worklist:
        text = translations.get(str(item["i"]))
        if text is None:
            missing.append(item["i"])
            continue
        if placeholders(text) != placeholders(item["source"] or item["key"]):
            rejected.append((item["i"], item["source"], text))
            continue
        path = item["catalog"]
        if not path.endswith(".xcstrings"):
            rejected.append((item["i"], f"not a string catalog: {path}", text))
            continue
        if path not in catalogs:
            file = pathlib.Path(path)
            catalogs[path] = json.loads(file.read_text(encoding="utf-8")) if file.exists() else {
                "sourceLanguage": "en", "strings": {}, "version": "1.0"}
        entry = catalogs[path]["strings"].setdefault(item["key"], {})
        if item["note"] and "comment" not in entry:
            entry["comment"] = item["note"]
        entry.setdefault("localizations", {})[language] = {
            "stringUnit": {"state": "translated", "value": text}
        }
        written += 1

    for path, catalog in catalogs.items():
        catalog["strings"] = dict(sorted(catalog["strings"].items()))
        pathlib.Path(path).write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"wrote {written} translations into {sorted(catalogs)}")
    if missing:
        print(f"missing translations for items: {missing}")
    for number, source, text in rejected:
        print(f"REJECTED {number}: {source!r} -> {text!r}")
    return 1 if (missing or rejected) else 0


if __name__ == "__main__":
    sys.exit(main())
