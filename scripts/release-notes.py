#!/usr/bin/env python3
"""Write the matching released changelog entry for a GitHub Release."""

import argparse
import pathlib
import re
import sys


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("version")
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()

    changelog = pathlib.Path("CHANGELOG.md").read_text(encoding="utf-8")
    heading = re.search(rf"^## {re.escape(args.version)}(?:\s|$).*", changelog, re.MULTILINE)
    if heading is None:
        sys.exit(f"CHANGELOG.md needs a released entry for {args.version} before tagging.")
    following = re.search(r"^## ", changelog[heading.end() :], re.MULTILINE)
    end = heading.end() + following.start() if following else len(changelog)
    notes = changelog[heading.end() : end].strip()
    if not notes:
        sys.exit(f"CHANGELOG.md entry for {args.version} is empty.")
    args.output.write_text(notes + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
