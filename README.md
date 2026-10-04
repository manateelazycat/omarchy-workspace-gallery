# Omarchy Workspace Gallery

English | [简体中文](README.zh-CN.md)

https://github.com/user-attachments/assets/f2a784c9-a5dc-433e-afa6-f3d038c70133

[Workspace compaction animation](assets/workspace-gallery-compaction-animation.mp4)

A gesture-driven workspace gallery with live previews and seamless drag-and-drop window management.

## Requirements

- Omarchy Quattro with its built-in Quickshell and Hyprland Lua configuration.
- No additional third-party binaries or network services are required at runtime.

## Interaction

- Press `Super+A` to open or close the gallery.
- Make a deliberate three-finger swipe up and release to open the gallery;
  short swipes are ignored to prevent accidental activation.
- Swipe three fingers down to close it.
- Swipe three fingers left or right while open to move continuously between
  workspaces; releasing commits the switch or springs back based on distance
  and velocity.
- While the gallery is open, pinch inward with two fingers or press `Down` to
  compact all occupied workspaces into consecutive numeric slots. Workspace
  order and monitor assignment are preserved.
- The top 20% of the screen shows occupied workspaces and one empty workspace
  at the end. Dropping a window there creates the next empty workspace.
- On multiple monitors, each preview shows only that monitor's workspaces and
  its own final empty workspace.
- The bottom 80% shows the selected workspace at a larger scale.
- Leaving the gallery applies each monitor's selected workspace independently.
- Drag a window between the top thumbnails and the large preview, including
  across monitors, to move it into the workspace under the pointer.
- Click a top workspace to select it; click a window in the large preview to focus it and leave the gallery.
- While the gallery is open, press the left and right arrow keys or `H`/`L`
  to select workspaces. Press `Enter`, `Space`, or `Esc` to focus the selected
  workspace and close the gallery.
- `Super+W` closes the most recently focused window in the selected workspace;
  outside the gallery it keeps its normal close-active-window behavior.
- Add the Workspace Gallery button to the right side of the bar. For an existing panel-only installation, run `omarchy plugin disable io.github.manateelazycat.workspace-gallery` and then `omarchy bar put io.github.manateelazycat.workspace-gallery --section right`. The bar entry also loads the gallery panel. Left click toggles the gallery. Its right-click menu offers “默认” (Default) and “关闭窗口切换工作区” (Switch workspace after closing a window); Default is selected initially and the choice is saved in the bar configuration.
- In the second mode, closing the last window on the focused monitor's active workspace with `Super+W` switches to the most recently visited occupied workspace on that monitor. If the recent workspace is empty, the plugin chooses another occupied workspace on that monitor.

Outside the gallery, three-finger horizontal swipes continue switching Hyprland workspaces.

## Install

```bash
omarchy plugin add https://github.com/manateelazycat/omarchy-workspace-gallery.git --enable --yes
~/.config/omarchy/plugins/io.github.manateelazycat.workspace-gallery/scripts/gestures install
```

The gesture installer adds the `Super+A` and `Super+W` shortcuts and gestures
in a clearly marked block in `~/.config/hypr/input.lua`, creates a timestamped
backup, reloads Hyprland, and validates the configuration.

`Super+W` uses the gallery's close behavior while the plugin is running. If
the plugin is disabled, removed, or Quickshell is unavailable, it falls back
to Hyprland's native close action for the window focused when the key was
pressed, even if the managed block is still present.

After updating an existing installation, rerun the installer to replace the
old shortcut binding, then restart the shell to load the IPC handler:

```bash
~/.config/omarchy/plugins/io.github.manateelazycat.workspace-gallery/scripts/gestures install
omarchy restart shell
```

## Remove

Remove the managed shortcut and gesture block before removing the plugin:

```bash
~/.config/omarchy/plugins/io.github.manateelazycat.workspace-gallery/scripts/gestures uninstall
omarchy plugin remove io.github.manateelazycat.workspace-gallery --yes
```

`omarchy plugin remove` does not clean up the managed block. If the plugin
has already been removed, run `./scripts/gestures uninstall` from a checkout
of this repository to remove the leftover shortcuts and gestures. This also
restores native `Super+W` for installations that still have the old binding.

## Development

Tests require Node.js, Python 3, and a Lua interpreter:

```bash
node --test
omarchy plugin validate .
qmllint -I "${OMARCHY_PATH:-/usr/share/omarchy}/shell" \
  Gallery.qml GalleryWidget.qml GalleryWindow.qml OverviewWindow.qml
```

After syncing local changes into an installed plugin, run `omarchy restart shell`.
Hot reload can leave an already open gallery using its previous QML components.

## Credits

The live preview, Hyprland data model, wallpaper integration, and drag-and-drop foundations are adapted from [Overview Workspaces](https://github.com/iamcheyan/omarchy-overview-workspaces) by HANCORE, licensed under MIT. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

Omarchy Workspace Gallery is licensed under the GNU General Public License
version 3.0 only (`GPL-3.0-only`). Vendored and adapted third-party portions
retain their original MIT license; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
