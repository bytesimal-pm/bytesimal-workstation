# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal Wayland desktop config for Arch Linux: **labwc** (compositor) + **quickshell** (bar and wallpaper, QML) + **wofi** (launcher), with a black/white translucent "glass" theme. There is no build step and no test suite — everything is config that gets symlinked into place.

## Install / deploy model

`./install.sh` is the single entry point. It installs missing repo packages via `sudo pacman -S --needed`, bootstraps `yay` from the AUR if absent and installs the `AUR_PACKAGES` list with it, enables the PipeWire user services (all skipped with `--no-pkgs`), then **symlinks each top-level folder into its config location** (`labwc/` → `~/.config/labwc`, `quickshell/` → `~/.config/quickshell`, fonts → `~/.local/share/fonts/...`, etc.), refreshes the font cache, sets the GTK dark color-scheme, and runs `labwc -r`.

Because the folders are symlinked wholesale, **editing a file in this repo is immediately live** — a new file dropped into `labwc/` is picked up without touching `install.sh`. Only add a `link` line when introducing a new top-level folder.

## Applying changes

| Changed | How to apply |
|---|---|
| `labwc/rc.xml`, `labwc/themerc-override`, `labwc/environment` | `labwc -r` (reloads on SIGHUP) |
| `labwc/autostart` | **Not** reloaded by `labwc -r` — only runs at session start. Start the process manually to test. |
| `quickshell/shell.qml` | Restart the bar: `pkill -x qs; cd quickshell && setsid qs -p shell.qml >/dev/null 2>&1 &` |
| `wofi/*` | Nothing — wofi reads config/style on each launch |
| `fontconfig/`, `fonts/` | `fc-cache -f`; verify with `fc-match` (see below) |

Check the live bar's log for QML warnings: `qs log -t 40` (add `-i <id>` from `qs list --all` if it can't find the instance). Smoke-test a QML change without disturbing the live bar: `cd quickshell && timeout 4 qs -p shell.qml` — exit code 143 (killed by timeout) with no output means it loaded cleanly.

## quickshell/shell.qml — things that will bite you

- **Hex colors are `#AARRGGBB` in QML (alpha first)**, not CSS's `#RRGGBBAA`. `"#ffffff26"` is opaque yellow, not translucent white. labwc's `themerc-override` uses the *opposite* convention (`#rrggbbaa`, alpha last) and wofi uses CSS `rgba()`. The same visual color is spelled three different ways across this repo.
- A `PanelWindow` needs `surfaceFormat.opaque: false` for any translucent `color` to composite; otherwise it renders opaque white.
- `DesktopEntries` scans `.desktop` files **asynchronously** and `heuristicLookup()` is a method call with no binding dependency. A `source:` binding that only calls it evaluates once (before the scan finishes) and never re-runs. The task icon binding deliberately reads `DesktopEntries.applications.values` first to register a dependency — keep that line.
- `SystemTrayItem.icon` is already a full image URL (`image://qspixmap/...`). Never pass it through `Quickshell.iconPath()` — that produces `image://icon/image://qspixmap/...` and renders a placeholder square.
- A nested `RowLayout` whose children don't set `fillWidth` has its **maximum** width capped at their combined width, so `Layout.fillWidth` on the container silently does nothing. The taskbar's trailing `Item { Layout.fillWidth: true }` spacer exists to lift that cap.
- A Layout nested in a Layout has `Layout.fillWidth: true` **by default**. Any sibling section that shouldn't grow (the tray) must set `Layout.fillWidth: false`, otherwise it competes with the taskbar for spare width — invisible while windows are open, but with zero windows the taskbar collapsed to a small empty bordered box.
- `ToplevelManager`/`DesktopEntries` bind lazily on first access. Diagnostic scripts that touch them inside a `Timer` will read empty lists; reference them at startup (e.g. a top-level property) first.
- `RowLayout`/`Item` have no `font` property — font family must be set on each `Text`.
- A **magenta/black checkerboard** in place of an icon is Quickshell's "icon not found" placeholder (`Image.status` still reports `Ready`, so you can't detect it in QML). If the icon exists on disk (`Quickshell.iconPath(name, true)` returns non-empty in a *fresh* `qs`), the running bar just predates the package install: Qt's icon loader caches theme lookups per process. Restart the bar; no code change needed.
- When screenshotting a test `PanelWindow` with `grim`, don't anchor it at the top-left — it sits under the live bar and you capture the real bar instead of your test.

To debug layout or icon problems, don't guess from screenshots: copy `shell.qml` to the scratchpad, inject `console.log` of geometry/`Image.status`, and run it with `timeout`. That approach found every bug above.

## labwc config notes

- A modifier-only keybind (bare Super) must use the keysym name plus `onRelease="yes"`: `<keybind key="Super_L" onRelease="yes">`. `key="W"` does not work.
- `Execute` uses `execvp` directly, no shell. Wrap anything with pipes/`||` in `sh -c "..."` (XML-escape the quotes as `&quot;`).
- `themerc-override` layers on top of the built-in theme without needing a theme package; available keys are in `labwc-theme(5)` (`zcat /usr/share/man/man5/labwc-theme.5.gz | col -b`). `man` is not installed on this machine.
- The example configs shipped with the package live in `/usr/share/doc/labwc/` (`rc.xml.all` documents every option).
- Keyboard layouts are XKB env vars in `labwc/environment` (`XKB_DEFAULT_LAYOUT=us,th`, `XKB_DEFAULT_OPTIONS=grp:win_space_toggle` for Super+Space). Layout names: `/usr/share/X11/xkb/rules/evdev.lst`; toggle options: `grep 'grp:' evdev.lst`. Don't bind the toggle chord in `rc.xml` — labwc consumes it first.

## Fonts

- **CommitMono Nerd Font Mono** is the UI font (bar, labwc titlebars, wofi). Only the `Mono` variant of the Nerd Font zip is committed.
- **TH Sarabun New** is scoped to Thai text only via `fontconfig/conf.d/49-th-sarabun.conf`. Verify scoping with `fc-match sans-serif:lang=th` (should be Sarabun) vs `fc-match sans-serif:lang=en` (should not).
- The committed Sarabun TTFs are **not the upstream files**: their glyphs are pre-scaled 1.4× by `fonts/THSarabunNew/rescale.py` because upstream draws them tiny in the em-square. Don't try to fix the size with a fontconfig `pixelsize` edit — Firefox, Chromium and Qt ignore it (only Pango/GTK honor it). To re-import upstream files, run the script on them (`pip install fonttools`).
- Firefox and other long-running apps cache the font list per process; after changing font files, `fc-cache -f` and restart the app.
- Cyrillic/CJK come from the `noto-fonts` / `noto-fonts-cjk` packages, not files in this repo.
