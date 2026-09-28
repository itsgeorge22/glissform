#!/usr/bin/env python3
"""Add one exact public Glissform DMG to the signed Sparkle feed."""

import argparse
import pathlib
import re
import shutil
import sys
import xml.etree.ElementTree as ET


SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def spark(name: str) -> str:
    return f"{{{SPARKLE}}}{name}"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--existing", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True, type=int)
    parser.add_argument("--url", required=True)
    parser.add_argument("--signature", required=True)
    parser.add_argument("--size", required=True, type=int)
    parser.add_argument("--minimum-os", required=True)
    args = parser.parse_args()

    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-(?:alpha|beta|rc)\.\d+)?", args.version):
        sys.exit("Unsupported release version.")
    if args.build <= 0 or args.size <= 0:
        sys.exit("Build number and DMG size must be positive.")
    if not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", args.minimum_os):
        sys.exit("Invalid minimum macOS version.")
    if not re.fullmatch(r"[A-Za-z0-9+/]{86}==", args.signature):
        sys.exit("Invalid Sparkle EdDSA signature.")
    expected_url = f"https://glissform.app/downloads/Glissform-{args.version}.dmg"
    if args.url != expected_url:
        sys.exit(f"The enclosure must be {expected_url}.")

    if args.existing and args.existing.is_file():
        root = ET.parse(args.existing).getroot()
        channel = root.find("channel")
        if root.tag != "rss" or channel is None:
            sys.exit("Existing appcast is not RSS with a channel.")
    else:
        root = ET.Element("rss", {"version": "2.0"})
        channel = ET.SubElement(root, "channel")
        ET.SubElement(channel, "title").text = "Glissform updates"
        ET.SubElement(channel, "link").text = "https://glissform.app/"
        ET.SubElement(channel, "description").text = "Published Glissform app updates"

    highest_build = 0
    for item in channel.findall("item"):
        prior_version = item.findtext(spark("shortVersionString"))
        prior_build = item.findtext(spark("version"))
        if prior_build is None or not prior_build.isdecimal():
            sys.exit("Existing appcast contains an item without a numeric build number.")
        highest_build = max(highest_build, int(prior_build))
        if prior_version == args.version or prior_build == str(args.build):
            enclosure = item.find("enclosure")
            if (
                prior_version == args.version
                and prior_build == str(args.build)
                and enclosure is not None
                and enclosure.get("url") == args.url
                and enclosure.get("length") == str(args.size)
                and enclosure.get(spark("edSignature")) == args.signature
            ):
                shutil.copyfile(args.existing, args.output)
                return
            sys.exit("Existing appcast has a different item for this version or build.")

    if args.build <= highest_build:
        sys.exit(f"Build {args.build} must exceed the appcast's latest build {highest_build}.")

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Glissform {args.version}"
    ET.SubElement(item, "link").text = "https://glissform.app/"
    ET.SubElement(item, spark("version")).text = str(args.build)
    ET.SubElement(item, spark("shortVersionString")).text = args.version
    ET.SubElement(item, spark("minimumSystemVersion")).text = args.minimum_os
    if "-" in args.version:
        ET.SubElement(item, spark("channel")).text = "beta"
    ET.SubElement(
        item,
        "enclosure",
        {
            "url": args.url,
            "length": str(args.size),
            spark("edSignature"): args.signature,
            "type": "application/octet-stream",
        },
    )
    channel.insert(3, item)
    args.output.write_bytes(ET.tostring(root, encoding="utf-8", xml_declaration=True))


if __name__ == "__main__":
    main()
