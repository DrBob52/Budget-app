#!/usr/bin/env python3
"""Fails when an exported XLIFF has strings without a finished translation.

Usage: check_localizations.py <localization export dir> [--report-only]

Prints one line per missing unit: MISSING<TAB>file<TAB>id<TAB>source (id and source JSON-encoded),
so the list can be copied straight out of the CI log.
"""
import json
import pathlib
import sys
import xml.etree.ElementTree as ET

NS = {"x": "urn:oasis:names:tc:xliff:document:1.2"}
DONE_STATES = {"translated", "final", "signed-off", "needs-review-translation"}


def main() -> int:
    root = pathlib.Path(sys.argv[1])
    report_only = "--report-only" in sys.argv
    xliffs = sorted(root.rglob("*.xliff"))
    if not xliffs:
        print(f"No .xliff files found under {root}")
        return 1
    missing = 0
    total = 0
    for xliff in xliffs:
        tree = ET.parse(xliff)
        for file_node in tree.getroot().findall("x:file", NS):
            original = file_node.get("original", "?")
            for unit in file_node.iter(f"{{{NS['x']}}}trans-unit"):
                if unit.get("translate") == "no":
                    continue
                total += 1
                source = unit.find("x:source", NS)
                target = unit.find("x:target", NS)
                state = target.get("state") if target is not None else None
                text = (target.text or "").strip() if target is not None else ""
                if not text or (state is not None and state not in DONE_STATES):
                    missing += 1
                    print("MISSING\t{}\t{}\t{}".format(
                        original,
                        json.dumps(unit.get("id")),
                        json.dumps(source.text if source is not None else ""),
                    ))
    print(f"{missing} of {total} strings are missing a translation in {[p.name for p in xliffs]}")
    return 0 if (missing == 0 or report_only) else 1


if __name__ == "__main__":
    sys.exit(main())
