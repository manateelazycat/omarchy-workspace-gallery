# Omarchy Workspace Gallery

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

Outside the gallery, three-finger horizontal swipes continue switching Hyprland workspaces.

## Install

```bash
omarchy plugin add https://github.com/manateelazycat/omarchy-workspace-gallery.git --enable --yes
~/.config/omarchy/plugins/io.github.manateelazycat.workspace-gallery/scripts/gestures install
```

The gesture installer adds the `Super+A` shortcut and gestures in a clearly
marked block in `~/.config/hypr/input.lua`, creates a timestamped backup,
reloads Hyprland, and validates the configuration.

## Remove

Remove the managed shortcut and gesture block before removing the plugin:

```bash
~/.config/omarchy/plugins/io.github.manateelazycat.workspace-gallery/scripts/gestures uninstall
omarchy plugin remove io.github.manateelazycat.workspace-gallery --yes
```

## Development

```bash
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
