# Kids mode, apps and themes: what a child install comes with

Rev 1, 2026-09-01. Branch `kids/child-apps-themes`, cut from `kids/child-profile`; its own PR after the child profile lands.

## Direction

DHH, on the child profile: "If child, then we trigger a different install profile. That's what'll include the different apps and different themes." And the boundary: "I don't want to build a panopticon for teenagers. ... for me, this is chiefly about a preteen config." Peter's daughter, eleven, is the first tester. Others are working on child-friendly themes; this branch is the infrastructure they plug into, plus one placeholder theme so a child install has somewhere to start.

## Decisions

- **Apps are the bindings and the menu, not the package set.** On quattro the preinstalled "apps" a kid would meet are the Super+Shift web-app and TUI bindings and the menu; there is no separate web-app install step. A child install keeps the bindings a kid can use (browser, files, editor, music, Obsidian, Omawrite, YouTube, Google Photos, Google Maps) and leaves out the work, chat, and social ones (Tmux, Herdr, Docker, Signal, 1Password, ChatGPT, Grok, HEY calendar and mail, WhatsApp, Google Messages, X, X Post); Khan Academy and Wikipedia come in on the freed keys. The menu's Community link to Discord is off. Peter named Discord and X; the rest follow the same line for an eleven-year-old.
- **Native packages are untouched for now.** The base set carries nothing a preteen should not see, and pulling packages out of it ripples into the install scripts (Docker's firewall rules, for one). `install/omarchy-child.packages` already adds packages on child installs; a child app that belongs on every kid's machine goes there. Blocking an installed app is the app list's job (`plans/kids-apps.md`).
- **Themes are a list, and the list is the infrastructure.** `install/omarchy-child.themes` names the themes a child install offers, first line first; `omarchy-theme-offered` is the predicate the switcher and `omarchy-theme-list` ask; `install/user/theme.sh` starts a child install on the first name. A "Me" install offers everything, a child install without the list offers everything, and the kid's own `~/.config/omarchy/themes` is always offered. Contributors add a theme under `themes/` and name it in the list.
- **Bubblegum is the placeholder**: a light pink-and-lilac palette, `Yaru-magenta` icons, a pink keyboard, and the Catppuccin Latte editor themes, complete enough to switch to and easy to replace or rename. Its backgrounds are two pictures Peter chose for his daughter: a spring meadow in the theme's own pastels first, which the switcher previews since the theme ships no screenshot, and a painted dusk over a mountain lake second.

## Naming

| What | Name |
| --- | --- |
| Profile predicate in Lua | `o.child_install()` in `default/hypr/helpers.lua`, reading `/etc/omarchy/profile` (or `OMARCHY_PROFILE_FILE`) |
| Bindings | `default/hypr/bindings/applications.lua`, the preinstalled block split by `o.child_install()` |
| Menu | `learn.community` guarded with `"when":"! omarchy-profile-child"` |
| Theme list | `install/omarchy-child.themes` |
| Theme predicate | `bin/omarchy-theme-offered <theme>` (hidden), asked by `omarchy-theme-list` and `omarchy-theme-switcher` |
| Default theme | `install/user/theme.sh`, first name of the list on a child install |
| Placeholder | `themes/bubblegum/` |

## Tests

`test/shell.d/child-apps-themes-test.sh`: the bindings under both profiles through the Lua harness the Hyprland tests use, with no key collisions on the child set; the menu guard; `omarchy-theme-offered` against a scratch tree in both profiles, with and without the list, and for the kid's own theme; both callers asking it; the switcher's cache keyed on the list; the default theme under both profiles through `install/user/theme.sh`; and the shipped list naming real themes with a complete placeholder first.

## Later

A parent-side `omarchy-parent themes` to pick which of the offered themes the kid sees (DHH's "Themes" under `omarchy-parent`), and a real preview screenshot for Bubblegum once it has run on a machine.
