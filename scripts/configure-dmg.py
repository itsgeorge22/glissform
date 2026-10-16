#!/usr/bin/env python3
"""Write Finder layout metadata without launching Finder (also works in CI)."""

import json
import sys
from pathlib import Path

from ds_store import DSStore
from mac_alias import Alias

if len(sys.argv) != 3:
    raise SystemExit("Usage: configure-dmg.py <mounted-volume> <layout.json>")

volume = Path(sys.argv[1]).resolve()
layout = json.loads(Path(sys.argv[2]).read_text())
background = volume / ".background" / "background.tiff"
if not volume.is_mount() or not background.is_file():
    raise SystemExit("Expected a mounted installer volume with its background artwork")

with DSStore.open(str(volume / ".DS_Store"), "w+") as store:
    store["."]["vSrn"] = ("long", 1)
    store["."]["icvl"] = ("type", b"icnv")
    store["."]["bwsp"] = {
        "WindowBounds": "{{200, 160}, {%d, %d}}" % (layout["width"], layout["windowHeight"]),
        "ShowStatusBar": False,
        "ContainerShowSidebar": False,
        "PreviewPaneVisibility": False,
        "SidebarWidth": 0,
        "ShowTabView": False,
        "ShowToolbar": False,
        "ShowPathbar": False,
        "ShowSidebar": False,
    }
    store["."]["icvp"] = {
        "viewOptionsVersion": 1,
        "backgroundType": 2,
        "backgroundImageAlias": Alias.for_file(str(background)).to_bytes(),
        "backgroundColorRed": 0.04,
        "backgroundColorGreen": 0.08,
        "backgroundColorBlue": 0.15,
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 100.0,
        "arrangeBy": "none",
        "showIconPreview": False,
        "showItemInfo": False,
        "labelOnBottom": True,
        "textSize": float(layout["textSize"]),
        "iconSize": float(layout["iconSize"]),
        "scrollPositionX": 0.0,
        "scrollPositionY": 0.0,
    }
    for name, position in layout["iconLocations"].items():
        store[name]["Iloc"] = tuple(position)

print("Configured installer window, background and draggable icons")
