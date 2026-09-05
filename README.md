# Window close buttons

An [Omarchy](https://omarchy.org) shell plugin. Hover a window's top-right
corner and a small close button appears, sized and positioned to fit inside
the gap between tiled windows; move away and it disappears. Hovering the
button also focuses that window (without moving your cursor), and clicking
it closes the window.

Colors follow the current theme's Hyprland active/inactive border tokens and
update live on a theme switch. Sizing derives from your configured
`general:gaps_in` and `general:border_size`, so it adapts to your Hyprland
config instead of using fixed pixel values.

## Install

```
omarchy plugin add https://github.com/axelfontaine/omarchy-window-close-buttons.git --enable
```

Plugins run as arbitrary, unsandboxed code inside your shell process —
review `Service.qml` before installing.

## Requirements

Tested against an Omarchy install using Hyprland's Lua config (`hl.dsp.*`
dispatchers). Written for a single-monitor setup; multi-monitor should work
but hasn't been tested.
