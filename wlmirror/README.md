# WL Mirror

Mirror Wayland outputs or windows using `wl-mirror`. Control mirroring from the bar widget with a dropdown panel.

## Plugin

- **Id:** `evergaster/wlmirror`
- **Widget entry:** `mirror` — bar widget that opens the mirror panel
- **Panel entry:** `panel` — dropdown panel with output and window selection
- **Service entry:** `monitor` — background process that watches for `wl-mirror` lifecycle changes

## Usage

Add the **Mirror** widget from **Settings → Bar → Add Widget**. Click the widget to open the panel with two sections:

- **Mirror** — Lists all connected outputs. Click an output to start mirroring it. Click again to stop.
- **Window** — Click "Select Window" to use the xdg-desktop-portal window picker (requires a portal backend like `xdg-desktop-portal-hyprland` or `xdg-desktop-portal-wlr`).

## Requirements

- `wl-mirror` must be installed and available on `PATH`.
- For window selection: a working xdg-desktop-portal backend.

## Settings

- **Output** — Default connector name to mirror (e.g. `eDP-1`, `HDMI-A-1`). Leave empty to use the panel selection.
- **Extra arguments** — Additional flags passed to `wl-mirror` (e.g. `--fullscreen`).

## Changelog

### 1.1.0
- Replaced control-center shortcut with bar widget + dropdown panel.
- Added panel with Mirror (output selection) and Window (portal window picker) sections.
- Dynamic output list that updates when the panel opens.
- Bumped plugin API to v4.
