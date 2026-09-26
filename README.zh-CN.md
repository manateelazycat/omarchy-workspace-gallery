# Omarchy Workspace Gallery

简体中文 | [English](README.md)

https://github.com/user-attachments/assets/f2a784c9-a5dc-433e-afa6-f3d038c70133

[工作区压缩动画](assets/workspace-gallery-compaction-animation.mp4)

一个由手势驱动的工作区总览，提供实时预览和流畅的窗口拖放管理。

## 依赖

- Omarchy Quattro，及其内置的 Quickshell 和 Hyprland Lua 配置。
- 运行时不需要额外的第三方程序或网络服务。

## 交互

- 按 `Super+A` 打开或关闭总览。
- 明确地用三指向上滑动并松开即可打开；短距离滑动会被忽略，避免误触。
- 三指向下滑动可关闭总览。
- 总览打开时，三指左右滑动可连续切换工作区；松开时根据滑动距离和速度决定切换还是弹回。
- 总览打开时，两指向内捏合或按 `Down`，可将所有已有窗口的工作区压缩到连续的数字位置。工作区顺序和显示器分配保持不变。
- 屏幕顶部 20% 显示已有窗口的工作区，末尾再显示一个空工作区。将窗口拖到那里会创建下一个工作区。
- 多显示器时，每块屏幕的预览只显示该显示器的工作区及其末尾的空工作区。
- 底部 80% 以较大尺寸显示选中的工作区。
- 退出总览时，各显示器会分别应用各自选中的工作区。
- 可以在顶部缩略图与下方大预览之间拖动窗口，包括跨显示器拖动；窗口会被放入指针所在的工作区。
- 点击顶部工作区可选中它；点击下方大预览中的窗口可聚焦该窗口并退出总览。
- 总览打开时，按左右方向键或 `H`／`L` 选择工作区。按 `Enter`、`Space` 或 `Esc` 会聚焦选中的工作区并关闭总览。
- `Super+W` 会关闭选中工作区里最近获得焦点的窗口；在总览之外则保留原有的关闭当前窗口行为。

总览关闭时，三指水平滑动仍按 Hyprland 的方式切换工作区。

## 安装

```bash
omarchy plugin add https://github.com/manateelazycat/omarchy-workspace-gallery.git --enable --yes
~/.config/omarchy/plugins/io.github.manateelazycat.workspace-gallery/scripts/gestures install
```

手势安装脚本会将 `Super+A` 快捷键和手势添加到 `~/.config/hypr/input.lua` 中一个明确标记的配置块，创建带时间戳的备份，重新加载 Hyprland，并验证配置。

## 卸载

移除插件前，先删除脚本管理的快捷键和手势配置块：

```bash
~/.config/omarchy/plugins/io.github.manateelazycat.workspace-gallery/scripts/gestures uninstall
omarchy plugin remove io.github.manateelazycat.workspace-gallery --yes
```

## 开发

```bash
omarchy plugin validate .
qmllint -I "${OMARCHY_PATH:-/usr/share/omarchy}/shell" \
  Gallery.qml GalleryWidget.qml GalleryWindow.qml OverviewWindow.qml
```

将本地修改同步到已安装的插件后，运行 `omarchy restart shell`。热重载可能让已打开的总览继续使用旧的 QML 组件。

## 致谢

实时预览、Hyprland 数据模型、壁纸集成和拖放基础改编自 HANCORE 的 [Overview Workspaces](https://github.com/iamcheyan/omarchy-overview-workspaces)，该项目按 MIT 协议发布。详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 协议

Omarchy Workspace Gallery 仅按 GNU General Public License v3.0（`GPL-3.0-only`）发布。随附和改编的第三方部分保留其原始 MIT 协议；详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
