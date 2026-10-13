# Magnifier

Launch a Wayland screen magnifier from Noctalia: click a bar widget, tap a
control-center tile, or bind a key that sends the plugin's IPC event.

The plugin is only a launcher. It ships no magnifier and installs nothing; it
runs one you already have and tells you where to get it when the binary is
missing.

## Plugin

| Field | Value |
| --- | --- |
| ID | `evergaster/magnifier` |
| Entries | Bar widget: `launcher`; Control-center shortcut: `tile` |
| IPC | `noctalia msg plugin evergaster/magnifier:launcher focused open` |

## Requirements

- **A Wayland compositor that exposes `wlr-layer-shell` and `wlr-screencopy`.**
  The plugin itself is compositor-agnostic — it just runs a command — but the
  magnifier it launches needs both protocols to capture the screen and draw its
  overlay. Compositors without `wlr-screencopy` cannot work: **GNOME/Mutter does
  not expose it, so GNOME is not supported**, and KWin is not supported either.
  Niri and most wlroots-based compositors (Sway, labwc, …) do expose it.
- **One magnifier installed** (see [Backends](#backends)). The plugin does not
  install it. If the binary is not found, clicking the widget shows an error
  naming the program and its repository.
- **Compatibility caveat.** Maggie is developed and tested only on **Niri**; its
  author lists Sway, Hyprland, KWin and GNOME as untested. hyprmag advertises
  itself as wlroots-compatible. Do not expect every backend to work on every
  compositor — if one misbehaves, try another or a custom command.

Because a magnifier's failure is silent (an empty or black overlay), the plugin
verifies that the binary exists before launching and reports a missing tool
through a notification with a link to the correct repository.

## Backends

The `backend` setting picks one. The plugin uses only flags documented in each
project's own README.

| Backend | Program | Documented flags | Zoom flag used |
| --- | --- | --- | --- |
| `maggie` (default) | `maggie` | `-z/--zoom`, `-d/--debug`, `--help`, `--version` | `-z <level>` |
| `hyprmag` | `hyprmag` | `-r/--radius`, `-s/--scale`, `-g/--draw-grid`, `--grid-colour` | `-s <level>` |
| `wooz` | `wooz` | `--map-close`, `--mouse-track`, `--output`, `--zoom-in`, `--invert-scroll` | not applied |
| `custom` | any command you write | — | — |

Only one backend is needed. Install one of:

- **Maggie** — <https://github.com/hced/maggie> — a frozen-frame magnifier
  (captures once at startup, then shows a cursor-following overlay). Prebuilt
  `maggie-linux.tar.gz` archives are published on its Releases page, and it can
  also be built from source with Cargo.
- **hyprmag** — <https://github.com/SIMULATAN/hyprmag> — a wlroots-compatible
  lens magnifier. Built with CMake; a `hyprmag-git` package also exists in some
  distributions. Note from its README: it "freezes" your displays while active.
- **wooz** — <https://github.com/negrel/wooz> — a zoom / magnifier utility, built
  with meson/ninja. **The upstream repository was archived (read-only) on
  2026-07-04**; it still works but is no longer maintained.

How you install these is up to you: use your distribution's packages, a
prebuilt release, or build from source. The plugin assumes the binary is on your
`PATH` unless you set `binary_path`.

For anything not listed above, choose the `custom` backend and write the command
yourself.

## Enabling the plugin

```sh
noctalia msg plugins enable evergaster/magnifier
```

To run it from a local checkout while developing, add the directory holding the
plugin as a source instead:

```sh
noctalia msg plugins source add dev path ~/dev/community-plugins
noctalia msg plugins enable evergaster/magnifier
```

Configure it from **Settings → Plugins** (the gear on the plugin's row). The
settings are plugin-level and shared by the bar widget, the control-center tile,
and IPC.

## Adding the widget to the bar

Define a named widget that points at the plugin entry, then list it in the bar
section where you want it. In `~/.config/noctalia/config.toml`:

```toml
[widget.magnifier]
type = "evergaster/magnifier:launcher"

[bar.default]
end = ["weather", "magnifier"]
```

`type` is the fully-qualified entry id `<author>/<plugin>:<entry>`. Use whichever
bar section fits (`start`, `center`, or `end`) and keep your existing entries —
the list replaces the section, it does not append.

**Control-center tile:** it has no separate placement file. Add it from
**Settings → Control Center → Shortcuts**, where the plugin exposes its `tile`
entry.

## Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `backend` | select | `maggie` | Which magnifier to launch: `maggie`, `hyprmag`, `wooz`, or `custom`. |
| `zoom` | int (1–9) | `3` | Initial zoom. Passed as `-z` to Maggie and `-s` to hyprmag. Not applied to `wooz` (its documented flag takes a percentage, which has no defined 1–9 mapping) or to `custom`. |
| `binary_path` | file | *(empty)* | Optional path to the magnifier executable. Empty means "look up the backend's binary on `PATH`". |
| `custom_command` | string | *(empty)* | Shell command run instead of a built-in backend. Only shown when `backend = custom`. Runs exactly as written — see [Notes](#notes). |
| `delay_ms` | int (0–10000) | `150` | Wait before launching. Lets an open panel or popup close before the magnifier captures the screen. Set to `0` to launch immediately. |

## IPC and keybindings

The widget's `onIpc` handler accepts the `open` event, which does the same thing
as a click:

```sh
noctalia msg plugin evergaster/magnifier:launcher focused open
```

`focused` targets the widget on the focused output; use `all` to reach every bar,
or a connector/bar name such as `DP-1:top`. The control-center `tile` also
accepts `open`, but it is not addressable from a bar target.

The shortcuts below are the equivalent binding per compositor. The primary
commands are the ones Noctalia's own Compositor Settings pages use; the classic
Hyprland `.conf` form is shown as an alternative.

### Niri

```kdl
binds {
    Mod+Z { spawn-sh "noctalia msg plugin evergaster/magnifier:launcher focused open"; }
}
```

### Hyprland

With the Lua configuration Noctalia documents:

```lua
local mainMod = "SUPER"
hl.bind(mainMod .. "+Z", hl.dsp.exec_cmd("noctalia msg plugin evergaster/magnifier:launcher focused open"))
```

Classic `hyprland.conf` (not shown in Noctalia's docs, but it is the standard
form):

```conf
bind = SUPER, Z, exec, noctalia msg plugin evergaster/magnifier:launcher focused open
```

### Sway

```conf
bindsym $mod+z exec noctalia msg plugin evergaster/magnifier:launcher focused open
```

### Umbriel

In `~/.config/umbriel/config.toml`:

```toml
[keybinds]
"Mod+Z" = "spawn:noctalia msg plugin evergaster/magnifier:launcher focused open"
```

## Publishing

### Thumbnail

Every plugin ships a `thumbnail.webp` — the card image in the plugin store and on
noctalia.dev. It must be **960×540 WebP**. Generate it with the official tool:

1. Open the [thumbnail generator](https://assets.noctalia.dev/plugins/thumbnail-generator.html).
2. Drop in a screenshot of the widget in the bar, set the title, a category tag,
   and an accent color.
3. Export and save the file as `magnifier/thumbnail.webp`.

### Pull request

1. Fork <https://github.com/noctalia-dev/community-plugins>.
2. Add the `magnifier/` directory: `plugin.toml`, `widget.luau`,
   `shortcut.luau`, `lib/launch.luau`, `translations/en.json`, `README.md`, and
   `thumbnail.webp`. The directory name must match the part of the id after the
   `/` exactly.
3. **Do not edit `catalog.toml`** — CI regenerates it on merge.
4. Open one PR for this plugin. CI validates the manifest, entry scripts,
   required files, and the thumbnail on every push. Bump `version` on every
   change.

## Notes

- **Processes spawned.** For a built-in backend the plugin runs the magnifier
  executable with an argument array (no shell). It also runs `sleep` with an
  argument array when `delay_ms` is greater than 0. For the `custom` backend it
  runs your command through the shell (`/bin/sh -c`).
- **`custom_command` is trusted code.** It runs exactly as you write it, with
  your user's privileges. Treat it like any shell command you type yourself.
- **Filesystem and network.** The plugin reads no files and makes no network
  requests. It writes nothing.
- **Single instance.** Before launching, the plugin checks running processes
  (`noctalia.processMatches`) and shows an informational notification instead of
  starting a second overlay. A `custom` command has no known process name, so it
  is never guarded.
- **Missing backend.** If the selected binary is absent, an error notification
  names the program and links to its repository. If `custom` is selected with an
  empty command, an error notification explains what to set.
