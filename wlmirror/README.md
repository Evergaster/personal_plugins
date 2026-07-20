# WL Mirror

Mirror a Wayland output to another display using `wl-mirror`. Toggle mirroring from the control center with a single click.

## Plugin

- **Id:** `evergaster/wlmirror`
- **Shortcut entry:** `toggle` — control-center tile to start/stop mirroring
- **Service entry:** `monitor` — background process that watches for `wl-mirror` lifecycle changes

## Usage

Add the **Mirror** shortcut from **Settings → Control Center → Shortcuts**. Click the tile to toggle mirroring on the configured output (or the currently focused output by default). Right-click to see the current configuration.

## Requirements

- `wl-mirror` must be installed and available on `PATH`.

## Settings

- **Output** — Connector name to mirror (e.g. `eDP-1`, `HDMI-A-1`). Leave empty to mirror the focused output.
- **Extra arguments** — Additional flags passed to `wl-mirror` (e.g. `--fullscreen`).
