# Omarchy Workspace Gallery

A gesture-driven workspace gallery with live previews and seamless drag-and-drop window management.

## Interaction

- Make a deliberate three-finger swipe up and release to open the gallery;
  short swipes are ignored to prevent accidental activation.
- Swipe three fingers down to close it.
- Swipe three fingers left or right while open to move continuously between
  workspaces; releasing commits the switch or springs back based on distance
  and velocity.
- The top 20% of the screen shows every workspace as a live thumbnail.
- The bottom 80% shows the selected workspace at a larger scale.
- Drag a window between the top thumbnails and the large preview to move it.
- Click a top workspace to select it; click a window in the large preview to focus it and leave the gallery.
- Press `Esc` to focus the selected workspace and close the gallery. Arrow
  keys and `H`/`L` select workspaces.

Outside the gallery, three-finger horizontal swipes continue switching Hyprland workspaces.

## Install

```bash
omarchy plugin add https://github.com/manateelazycat/omarchy-workspace-gallery.git --enable --yes
~/.config/omarchy/plugins/io.github.manateelazycat.workspace-gallery/scripts/gestures install
```

The gesture installer adds a clearly marked block to `~/.config/hypr/input.lua`, creates a timestamped backup, reloads Hyprland, and validates the configuration.

## Remove

Remove the managed gesture block before removing the plugin:

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

## Credits

The live preview, Hyprland data model, wallpaper integration, and drag-and-drop foundations are adapted from [Overview Workspaces](https://github.com/iamcheyan/omarchy-overview-workspaces) by HANCORE, licensed under MIT. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

Omarchy Workspace Gallery is licensed under the GNU General Public License
version 3.0 only (`GPL-3.0-only`). Vendored and adapted third-party portions
retain their original MIT license; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
