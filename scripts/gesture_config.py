#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import pathlib
import shutil
import sys

START = "-- >>> omarchy-workspace-gallery >>>"
END = "-- <<< omarchy-workspace-gallery <<<"
BLOCK = f'''{START}
-- Managed by Workspace Gallery. Use scripts/gestures uninstall to remove.
hl.bind("SUPER + A", hl.dsp.global("quickshell:workspaceGalleryToggle"), {{
  description = "Toggle Workspace Gallery",
}})
hl.unbind("SUPER + W")
hl.bind("SUPER + W", hl.dsp.global("quickshell:workspaceGalleryCloseWindow"), {{
  description = "Close window",
}})
hl.gesture({{
  fingers = 3,
  direction = "vertical",
  action = {{
    start = function(e)
      hl.dispatch(hl.dsp.event("workspace-gallery-vertical,start," .. e.delta.y .. "," .. e.time_ms))
    end,
    update = function(e)
      hl.dispatch(hl.dsp.event("workspace-gallery-vertical,update," .. e.delta.y .. "," .. e.time_ms))
    end,
    finish = function(e)
      hl.dispatch(hl.dsp.event("workspace-gallery-vertical,finish," .. tostring(e.cancelled) .. "," .. e.time_ms))
    end,
  }},
}})
hl.gesture({{
  fingers = 3,
  direction = "horizontal",
  action = {{
    start = function(e)
      hl.dispatch(hl.dsp.event("workspace-gallery-swipe,start," .. e.delta.x .. "," .. e.time_ms))
    end,
    update = function(e)
      hl.dispatch(hl.dsp.event("workspace-gallery-swipe,update," .. e.delta.x .. "," .. e.time_ms))
    end,
    finish = function(e)
      hl.dispatch(hl.dsp.event("workspace-gallery-swipe,finish," .. tostring(e.cancelled) .. "," .. e.time_ms))
    end,
  }},
}})
hl.gesture({{
  fingers = 2,
  direction = "pinch",
  action = {{
    finish = function(e)
      hl.dispatch(hl.dsp.event("workspace-gallery-compact,trigger"))
    end,
  }},
}})
{END}
'''


def strip_managed_block(text: str) -> str:
    start = text.find(START)
    if start < 0:
        return text
    end = text.find(END, start)
    if end < 0:
        raise RuntimeError(f"Found {START!r} without its closing marker")
    end += len(END)
    if end < len(text) and text[end] == "\n":
        end += 1
    return text[:start].rstrip() + "\n" + text[end:].lstrip("\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("install", "uninstall"))
    args = parser.parse_args()

    target = pathlib.Path.home() / ".config" / "hypr" / "input.lua"
    if not target.is_file():
        print(f"Missing Hyprland input config: {target}", file=sys.stderr)
        return 1

    original = target.read_text(encoding="utf-8")
    try:
        cleaned = strip_managed_block(original)
    except RuntimeError as error:
        print(error, file=sys.stderr)
        return 1

    if args.action == "install":
        updated = cleaned.rstrip() + "\n\n" + BLOCK
    else:
        updated = cleaned.rstrip() + "\n"

    if updated == original:
        print(f"No changes needed in {target}")
        return 0

    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = target.with_name(f"{target.name}.bak-workspace-gallery-{stamp}")
    shutil.copy2(target, backup)
    target.write_text(updated, encoding="utf-8")
    print(f"Updated {target}")
    print(f"Backup: {backup}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
