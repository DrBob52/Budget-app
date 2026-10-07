#!/usr/bin/env python3
"""Lists untranslated strings from an exported XLIFF as a numbered worklist.

Usage: xliff_worklist.py <es.xliff> <worklist.json>

Each entry: {"i": n, "catalog": path, "key": key, "source": text, "note": comment}.
Translators fill a separate {"n": "translation"} map, so keys are never retyped.
"""
import json
import sys
import xml.etree.ElementTree as ET

NS = {"x": "urn:oasis:names:tc:xliff:document:1.2"}
DONE = {"translated", "final", "signed-off", "needs-review-translation"}


def main() -> None:
    tree = ET.parse(sys.argv[1])
    items = []
    for file_node in tree.getroot().findall("x:file", NS):
        original = file_node.get("original", "")
        for unit in file_node.iter(f"{{{NS['x']}}}trans-unit"):
            if unit.get("translate") == "no":
                continue
            target = unit.find("x:target", NS)
            state = target.get("state") if target is not None else None
            if target is not None and "".join(target.itertext()).strip() and (state is None or state in DONE):
                continue
            source = unit.find("x:source", NS)
            note = unit.find("x:note", NS)
            items.append({
                "i": len(items) + 1,
                "catalog": original,
                "key": unit.get("id"),
                "source": " | ".join(t.strip() for t in source.itertext() if t.strip()) if source is not None else "",
                "note": (note.text or "") if note is not None else "",
            })
    with open(sys.argv[2], "w", encoding="utf-8") as out:
        json.dump(items, out, ensure_ascii=False, indent=1)
    catalogs = sorted({item["catalog"] for item in items})
    print(f"{len(items)} strings need translation in {catalogs}")


if __name__ == "__main__":
    main()
