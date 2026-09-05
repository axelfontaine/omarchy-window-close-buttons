// Hover a window's top-right corner to reveal a small close button.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons

Item {
  id: service

  // Injected by omarchy-shell (the first-party service loader).
  property var shell: null

  // "general:gaps_in" is Hyprland's own name for the space between tiled
  // windows, fetched the same way Commons/Style.qml fetches gaps_out. That
  // config value is a per-window inset (each of the two neighboring windows
  // is pulled back by gaps_in), so the actual empty channel between two
  // window borders is 2x that. cornerGapRadius is 1px smaller than that
  // channel — the largest circle that couldn't clip a neighboring window if
  // it were centered on the corner.
  property int gapsIn: 5
  readonly property int cornerGapRadius: Math.max(1, service.gapsIn * 2 - 1)
  // Displayed circle is 150% of cornerGapRadius, shifted inward (see
  // circleInset) so 2/3 of its diameter lands inside the window and 1/3
  // stays in the gap — at these particular ratios that keeps the gap-side
  // protrusion at exactly cornerGapRadius, same as an unshifted circle would.
  readonly property int circleRadius: Math.round(service.cornerGapRadius * 1.5)
  readonly property int circleSize: service.circleRadius * 2
  // Distance the circle's center is pulled in from the window corner, along
  // both axes (a circle centered exactly on the corner splits 50/50).
  readonly property int circleInset: Math.round(service.circleRadius / 3)
  // The invisible hit/hover box has to be big enough to hold the fully
  // offset circle without clipping it against the panel's own edge.
  readonly property int hitSize: 2 * (service.circleRadius + service.circleInset) + 8

  Process {
    id: gapsInProc
    command: ["hyprctl", "-j", "getoption", "general:gaps_in"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var json = JSON.parse(text || "{}")
          var parts = String(json.css || "").match(/-?\d+(?:\.\d+)?/g) || []
          var n = parts.length > 0 ? Number(parts[0]) : Number(json.int)
          if (isFinite(n) && n >= 0) service.gapsIn = n
        } catch (e) {
          // hyprctl missing / Hyprland not running — leave the previous value.
        }
      }
    }
  }
  // "general:border_size" is the theme's active-window border width — the
  // circle's own outline is drawn at the same width for visual consistency.
  property int borderSize: 2

  Process {
    id: borderSizeProc
    command: ["hyprctl", "-j", "getoption", "general:border_size"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var json = JSON.parse(text || "{}")
          var n = Number(json.int)
          if (isFinite(n) && n >= 0) service.borderSize = n
        } catch (e) {
          // hyprctl missing / Hyprland not running — leave the previous value.
        }
      }
    }
  }
  // shell.toml has no inactive-window counterpart to its active-border
  // token, so this reads Hyprland's own live config directly instead.
  // getoption reports colors as a gradient string ("aarrggbb aarrggbb...
  // Ndeg"); only the first stop is used, same simplification flatColor
  // applies to the active-border token elsewhere in this file.
  property color inactiveBorderColor: Color.muted

  function firstGradientStopColor(raw) {
    var tokens = String(raw || "").trim().split(/\s+/)
    for (var i = 0; i < tokens.length; i++) {
      if (/^[0-9a-fA-F]{8}$/.test(tokens[i])) return "#" + tokens[i]
    }
    return null
  }

  Process {
    id: inactiveBorderProc
    command: ["hyprctl", "-j", "getoption", "general:col.inactive_border"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var json = JSON.parse(text || "{}")
          var color = service.firstGradientStopColor(json.gradient)
          if (color) service.inactiveBorderColor = color
        } catch (e) {
          // hyprctl missing / Hyprland not running — leave the previous value.
        }
      }
    }
  }
  Component.onCompleted: {
    gapsInProc.running = true
    borderSizeProc.running = true
    inactiveBorderProc.running = true
  }

  // "hyprland.active-border" is the theme's own token for this exact
  // purpose (shell.toml: "stay aligned with the current Hyprland
  // active-border gradient"); flatColor collapses a gradient string down
  // to its first stop, since a single Rectangle can't render an angle.
  // Both re-evaluate live on theme switch because Color.shellValues is
  // reassigned wholesale rather than mutated.
  readonly property color circleColor: Color.flatColor(Color.pick("hyprland.active-border", Color.accent), Color.accent)
  readonly property color glyphColor: Color.flatColor(Color.pick("hyprland.active-border-foreground", Color.foreground), Color.foreground)

  function mixColor(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }

  // HyprlandToplevel.address comes back as bare hex ("56538020a4f0"), unlike
  // lastIpcObject.address which is "0x"-prefixed — normalize before matching
  // or handing it to hyprctl.
  function normalizedAddress(addr) {
    if (typeof addr !== "string") return null
    var hex = addr.indexOf("0x") === 0 ? addr.slice(2) : addr
    return /^[0-9a-fA-F]+$/.test(hex) ? "0x" + hex : null
  }

  // Omarchy's Hyprland build routes `hyprctl dispatch <args>` through a Lua
  // eval (`hl.dispatch(<args>)`), so the classic "closewindow address:0x.."
  // string is not valid here — dispatchers are Lua calls under hl.dsp.*.
  // Verified against this install: hl.dsp.window.close({ address = ".." })
  // closes the targeted window regardless of focus.
  function closeWindow(addr) {
    var normalized = service.normalizedAddress(addr)
    if (!normalized) return
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.close({ address = \"" + normalized + "\" })"])
  }

  // hl.dsp.focus's "address" key isn't recognized (verified against this
  // install: hl.focus only accepts direction/monitor/window/urgent_or_last/
  // last) — the working form reuses classic Hyprland's "address:0x.."
  // window-selector syntax under the "window" key instead.
  //
  // Focusing this way normally warps the system cursor to the window's
  // center, which is wrong for a hover-triggered focus: the pointer is
  // already exactly where the user put it. Restoring the cursor's position
  // afterwards can't reliably beat that warp (it isn't synchronous with the
  // dispatch reply), so instead cursor:no_warps is toggled on for just the
  // dispatch's duration — config changes apply immediately, so there's no
  // warp to undo in the first place. The captured original value is
  // restored after (rather than hardcoding false) so this is a no-op for
  // anyone who already runs with no_warps set.
  function focusWindow(addr) {
    var normalized = service.normalizedAddress(addr)
    if (!normalized) return
    var script = "addr=\"$1\"; "
      + "orig=false; hyprctl -j getoption cursor:no_warps | grep -q '\"bool\": true' && orig=true; "
      + "hyprctl eval 'hl.config({ cursor = { no_warps = true } })' >/dev/null; "
      + "hyprctl dispatch \"hl.dsp.focus({ window = \\\"address:$addr\\\" })\"; "
      + "hyprctl eval \"hl.config({ cursor = { no_warps = $orig } })\" >/dev/null"
    Quickshell.execDetached(["bash", "-lc", script, "bash", normalized])
  }

  function screenForMonitor(monitor) {
    if (!monitor || !monitor.name) return null
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (screens[i].name === monitor.name) return screens[i]
    }
    return null
  }

  // Quickshell's Hyprland module keeps toplevel geometry current from IPC
  // events, but Hyprland has no discrete "resize finished" event to key a
  // refresh off of, so a light poll keeps corners glued to their window
  // through an edge-drag resize. This is an IPC round-trip, not a
  // subprocess spawn, so it's cheap enough to run continuously.
  Timer {
    interval: 400
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: Hyprland.refreshToplevels()
  }

  Variants {
    model: Hyprland.toplevels.values

    PanelWindow {
      id: cornerWindow
      required property var modelData

      readonly property var info: modelData ? modelData.lastIpcObject : null
      readonly property var targetScreen: service.screenForMonitor(modelData ? modelData.monitor : null)
      // Pinned windows stay on screen across a workspace switch even though
      // their own workspace is no longer the active one.
      readonly property bool onActiveWorkspace: modelData !== null && modelData.workspace !== null
        && (modelData.workspace.active === true || (info !== null && info.pinned === true))
      // info's "at"/"size" arrive as QVariantList, which marshals into QML as
      // an array-like object (indexable, has .length) rather than a real JS
      // Array, so Array.isArray() on it is always false — check shape instead.
      readonly property bool showable: onActiveWorkspace
        && info !== null && info.mapped !== false && info.hidden !== true
        && info.at && info.at.length === 2 && info.size && info.size.length === 2
        && targetScreen !== null
      readonly property bool isActiveWindow: modelData !== null && Hyprland.activeToplevel !== null
        && Hyprland.activeToplevel.address === modelData.address
      // Pressing on the circle and dragging off before releasing leaves
      // HoverHandler.hovered stuck at its pre-drag value — Qt only
      // re-evaluates hover on the next real pointer move, not on release —
      // so the circle would otherwise stay visible until the mouse moves
      // again. Sets true from the close TapHandler's own grab (which keeps
      // tracking the pointer through the drag regardless of bounds) and
      // clears as soon as a fresh hover cycle starts.
      property bool forceHidden: false

      screen: targetScreen
      visible: showable
      color: "transparent"

      WlrLayershell.namespace: "omarchy-window-close-button"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      implicitWidth: service.hitSize
      implicitHeight: service.hitSize

      anchors { left: true; top: true }
      margins.left: showable ? Math.round(info.at[0] + info.size[0] - targetScreen.x - service.hitSize / 2) : 0
      margins.top: showable ? Math.round(info.at[1] - targetScreen.y - service.hitSize / 2) : 0

      HoverHandler {
        id: hover
        onHoveredChanged: if (hovered) cornerWindow.forceHidden = false
      }

      Rectangle {
        id: circle
        // Pull left (into the window horizontally) and down (into the
        // window vertically) so the circle sits mostly inside the window.
        x: (parent.width - width) / 2 - service.circleInset
        y: (parent.height - height) / 2 + service.circleInset
        width: service.circleSize
        height: service.circleSize
        radius: width / 2
        // closeTap's own point stays accurate through a drag even once the
        // pointer leaves the circle (same reasoning as forceHidden above),
        // so it's what decides the pressed state rather than innerHover.
        readonly property bool pressedInside: closeTap.pressed
          && closeTap.point.position.x >= 0 && closeTap.point.position.y >= 0
          && closeTap.point.position.x <= width && closeTap.point.position.y <= height
        readonly property color pressedFillColor: service.mixColor(service.circleColor, Color.background, 0.5)
        readonly property color hoverFillColor: service.mixColor(pressedFillColor, Color.background, 0.5)
        // Idle (revealed but not precisely targeted) shows the theme's own
        // background fill, same as everything else in the shell; hovering
        // the circle dims it toward hoverFillColor, and holding the button
        // down over it goes to the stronger pressedFillColor, leaving the
        // glyph's own color untouched throughout.
        color: pressedInside ? pressedFillColor : (innerHover.hovered ? hoverFillColor : Color.background)
        border.color: cornerWindow.isActiveWindow ? service.circleColor : service.inactiveBorderColor
        border.width: service.borderSize
        opacity: (hover.hovered && !cornerWindow.forceHidden) ? 1 : 0
        scale: hover.hovered ? 1 : 0.7

        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
        Behavior on color { ColorAnimation { duration: 80 } }

        HoverHandler {
          id: innerHover
          cursorShape: Qt.PointingHandCursor
          onHoveredChanged: {
            if (!hovered || !cornerWindow.modelData) return
            var addr = cornerWindow.modelData.address
            if (Hyprland.activeToplevel && Hyprland.activeToplevel.address === addr) return
            service.focusWindow(addr)
          }
        }

        // Scoped to the circle itself (not the wider hit box the outer
        // HoverHandler above uses just to reveal it) so a click landing in
        // the hit box but outside the visible button doesn't close anything.
        TapHandler {
          id: closeTap
          acceptedButtons: Qt.LeftButton
          // Close on release, and only if the release still lands on the
          // circle — pressing down then dragging off before letting go
          // shouldn't close anything.
          gesturePolicy: TapHandler.ReleaseWithinBounds
          onTapped: service.closeWindow(cornerWindow.modelData.address)
          // ReleaseWithinBounds keeps this grab (and point tracking) through
          // the whole drag even once the pointer leaves the circle, so its
          // own release position is reliable ground truth for "did the
          // pointer end up outside the corner window entirely" — unlike
          // hover.hovered, which goes stale during the same drag.
          onPressedChanged: {
            if (pressed) return
            var absX = circle.x + closeTap.point.position.x
            var absY = circle.y + closeTap.point.position.y
            if (absX < 0 || absY < 0 || absX > cornerWindow.width || absY > cornerWindow.height) {
              cornerWindow.forceHidden = true
            }
          }
        }

        Text {
          anchors.centerIn: parent
          text: "✕"
          color: service.glyphColor
          font.pixelSize: parent.width * 0.6
          font.bold: true
        }
      }
    }
  }
}
