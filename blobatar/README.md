# Blobatar

A Blobatar desktop pet for [Noctalia](https://github.com/noctalia-dev/noctalia-shell).
The blob's expression follows your focus timer, battery, CPU, RAM, and
do-not-disturb state, so it looks busy when you are and glum when your laptop is
about to die.

The avatar is never drawn in Lua. Identity and pose come from the Blobatar
service over HTTPS; the plugin decides *which* pose to ask for, caches the SVG on
disk, and hands the local path to `ui.image`.

## Install

Add the source once, then enable the plugin:

```sh
noctalia msg plugins source add personal git https://github.com/Evergaster/personal_plugins.git
noctalia msg plugins enable evergaster/blobatar
```

Then add the **Blobatar** desktop widget from the desktop widget editor
(`noctalia msg desktop-widgets-edit`).

During development, point a source straight at a checkout so edits hot-reload:

```sh
noctalia msg plugins source add personal-dev path ~/personal_plugins
noctalia msg plugins enable evergaster/blobatar
```

> **Not an npm package.** There is a `blobatar` on npm along with an
> `@blobatar/react` component, but those are for JavaScript and React apps. They
> have nothing to do with this plugin, and installing them will not put a pet on
> your desktop.

## Expressions

The first matching rule wins:

| Situation | Expression |
| --- | --- |
| Expression chosen in the panel | that one |
| You clicked the pet (for ~2s) | `surprised` |
| Focus session running | `thinking` |
| Focus session finished | `love` |
| Focus session paused | `unsure` |
| Do not disturb on | `sleepy` |
| Battery ≤ 10% | `scared` |
| Battery ≤ 20% | `sad` |
| CPU ≥ 90% | `mad` |
| RAM ≥ 90% | `unsure` |
| CPU ≤ 20% and RAM ≤ 60% | `smug` |
| Otherwise | `idle` |

Turning **Reactions** off leaves the pet reacting only to the focus timer and to
clicks. Charging cancels the low-battery moods.

## Panel

The desktop widget cannot take focus, so the name field lives in the panel:

- **Name** — sets the string the blob is generated from. A plugin cannot write
  its own settings, so this is stored in the plugin's data directory as
  `profile.json` and takes precedence over the `name` setting until you press
  **Use setting** to clear it.
- **Focus** — start, pause, and reset a pomodoro of the configured length.
- **Expression** — pick any expression, or hand control back to the automatic
  rules.
- **Machine** — live CPU, RAM, battery, and do-not-disturb readout.

## CLI

The service accepts the same commands from the command line, which is handy for
keybindings:

```sh
noctalia msg plugin evergaster/blobatar:pet all start
noctalia msg plugin evergaster/blobatar:pet all pause
noctalia msg plugin evergaster/blobatar:pet all reset
noctalia msg plugin evergaster/blobatar:pet all poke
noctalia msg plugin evergaster/blobatar:pet all set_override wink
noctalia msg plugin evergaster/blobatar:pet all clear_override
noctalia msg plugin evergaster/blobatar:pet all set_name Umberto
noctalia msg plugin evergaster/blobatar:pet all clear_name
```

`set_override` and `set_name` take their argument as the trailing payload.
`set_override` ignores anything that is not a real expression, and `set_name`
ignores an empty name.

## Settings

| Setting | Default | Notes |
| --- | --- | --- |
| `name` | `evergaster` | Any string, including `/` and spaces |
| `size` | `256` | 64–1024; higher is sharper and heavier |
| `background` | `none` | `none`, `square`, `circle`, `squircle` |
| `gen` | `2` | Pins the name-to-blob mapping so the shape never changes |
| `lock_hue` / `hue` | off / `0` | Fixed colour instead of the one from the name |
| `lock_tone` / `tone` | off / `50` | Fixed tone, 0 (pale) to 100 (ink) |
| `reactions` | on | React to battery, CPU, RAM, and DND |
| `pomodoro_minutes` | `25` | 1–180 |
| `notify` | on | Notification when a session finishes |
| `widget_size` | `128` | Size on the desktop |
| `animate` | on | Breathing, bob, sway, hover, and a hop on tap |
| `show_progress` | on | Progress bar during a focus session |
| `show_status` | on | One-line caption under the blob |
| `accent` | `primary` | Progress bar colour |

## Animation

The pet is not a static picture. It imitates the motion of the web client, but
Noctalia's UI has no compositor and no transforms, so the motion is assembled
from the primitives that do exist.

**Body motion, in the widget box.** A volume-preserving breath (wider while it
rises, narrower as it settles) rides a vertical bob and a slower lateral sway on
a different period, so the two never read as one loop. Hovering widens the
amplitude a little, which is what gives the web version its "it noticed you"
feeling. Tapping plays an anticipation dip, a hop, and two diminishing bounces.

The picture is drawn smaller than the fixed widget box and the motion offsets are
measured from that margin, so the blob can never walk out and get clipped.
Geometry is rounded to a fraction of a pixel: the frame tick would otherwise
re-render 100 times a second to move the blob by an amount nobody can see.

**Eye motion does not happen, and it is a deliberate choice.** Blinking and
looking around are the obvious next step, and they were built and then removed.

The web client animates the face by styling the body and eyes separately.
`ui.image` renders one flat file, Noctalia's UI nodes have no transform or
compositor, and Qt's SVG renderer ignores SMIL — so a single file cannot move its
own eyes. The only mechanism left is to pre-render several whole-avatar poses and
swap the image source between them, which is how expression changes already work.

That was implemented, and it made the pet vanish and reappear several times a
minute: every source change reloads the texture and the node is blank for the
duration of the decode. The poses were correct — `tools/verify_poses.py` still
parses them and passes — but correct is not the point when the result flickers.
A pet that is always there beats a pet that blinks.

So the image source now changes only when the mood does. If Noctalia ever gains a
compositor, or an image node that can update its texture in place, the poses are
worth rebuilding; the service still cleans up their files in the meantime.

## Behaviour worth knowing

- **The focus timer is not persisted.** A session in progress is lost when the
  shell restarts; the pet returns to idle.
- **Each expression is a separate request.** The pose is baked into the SVG, so a
  new expression is a new download. Previously seen expressions are served from
  the cache immediately. A brand new expression waits ~0.7s to settle first, so a
  value oscillating around a threshold cannot spin the cache. The pet keeps
  showing the old expression meanwhile.
- **The cache is capped** at 40 avatars in `pluginDataDir()/avatars/`, pruned
  least-recently-used first. Dragging the hue slider generates cache keys quickly.
  Each avatar is the endpoint's original plus one file per pose, and a key's files
  are always removed as a group.
- **Offline is fine once cached.** Rendering uses a local file. If a download
  fails, the pet keeps the last avatar it had and the panel shows a warning.

## Requirements

- Noctalia with `plugin_api = 24`
- Outbound HTTPS to `blobatar.dev` on first fetch of each expression
- Qt with the SVG image plugin (present by default on most installs)
- Linux, for the battery reading from `/sys/class/power_supply`

## Licence

MIT.
