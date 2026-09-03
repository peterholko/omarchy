#!/bin/bash

source "$(dirname "$0")/base-test.sh"

# A child install (kids mode) gets a different app set and theme set than a
# "Me" install: the work, chat, and social web-app bindings stay out and two
# places to learn come in, the Discord link leaves the menu, and the theme
# switcher offers the child-friendly list, starting on its first theme.

require_command lua

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
child_marker="$test_tmp/profile-child"
printf 'child\n' >"$child_marker"

# The application bindings under a profile, one "keys<TAB>description" per line.
bindings_for() {
  local profile_file="$1" home="$test_tmp/home-$RANDOM"
  mkdir -p "$home/.config"
  HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" OMARCHY_PATH="$ROOT" OMARCHY_PROFILE_FILE="$profile_file" lua <<'LUA'
package.path = os.getenv("HOME") .. "/.config/?.lua;" .. os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path
hl = {
  dsp = { exec_cmd = function(command) return { kind = "exec", arg = command } end },
  bind = function(keys, dispatcher, opts)
    opts = opts or {}
    if opts.description then print(keys .. "\t" .. opts.description) end
  end,
}
require("default.hypr.helpers")
require("default.hypr.bindings.applications")
LUA
}

kid=$(bindings_for "$child_marker")
grown=$(bindings_for "$test_tmp/no-such-profile")
for gone in "X" "X Post" "ChatGPT" "Grok" "WhatsApp" "Google Messages" "Email" "Calendar" "Signal" "Docker" "Passwords" "YouTube" "Google Photos" "Music TUI"; do
  ! grep -q $'\t'"$gone"'$' <<<"$kid" || fail "a child install has no $gone binding"
  grep -q $'\t'"$gone"'$' <<<"$grown" || fail "a Me install keeps the $gone binding"
done
for kept in "Browser" "File manager" "Google Maps" "Music" "Obsidian" "Omawrite" "Terminal"; do
  grep -q $'\t'"$kept"'$' <<<"$kid" || fail "a child install keeps the $kept binding"
done
grep -q 'o.bind("SUPER + SHIFT + M", "Music", { tui = "cliamp", focus = true })' "$ROOT/default/hypr/bindings/applications.lua" || fail "a child install's Music key opens Cliamp rather than Spotify"
grep -q $'^SUPER + SHIFT + K\tKhan Academy$' <<<"$kid" && grep -q $'^SUPER + SHIFT + ALT + K\tWikipedia$' <<<"$kid" || fail "a child install gets Khan Academy and Wikipedia"
! grep -q 'Khan Academy\|Wikipedia' <<<"$grown" || fail "a Me install is unchanged"
[[ $(cut -f1 <<<"$kid" | sort | uniq -d) == "" ]] || fail "the child bindings do not collide" "$(cut -f1 <<<"$kid" | sort | uniq -d)"
pass "a child install's app bindings leave out the grown-up web apps and add places to learn"

grep -q '"learn.community": {[^}]*"when":"! omarchy-profile-child"' "$ROOT/default/omarchy/omarchy-menu.jsonc" || fail "the Discord community link stays off a child install's menu"
for row in install.package install.aur install.ai install.development install.editor install.terminal install.tui remove.package remove.ai remove.development learn.neovim learn.bash learn.tmux-keybindings learn.herdr-keybindings; do
  grep -q "\"$row\": {[^}]*\"when\":\"! omarchy-profile-child" "$ROOT/default/omarchy/omarchy-menu.jsonc" || fail "the $row row stays off a child install's menu"
done
for row in install.style install.browser install.gaming install.webapp install.service install.windows update.omarchy setup.security.fingerprint; do
  ! grep -q "\"$row\": {[^}]*\"when\":\"! omarchy-profile-child" "$ROOT/default/omarchy/omarchy-menu.jsonc" || fail "the $row row stays on a child install's menu for the parent"
done
pass "the menu keeps the Discord link, the package installers, and the developer rows off a child install"

# The launcher: a child install gets the listed entries and the child-only
# ones, no terminal entry, and none of the agent CLI stubs.
launcher_home="$test_tmp/launcher-home"
launcher_bin="$test_tmp/launcher-bin"
launcher_app_dir="$launcher_home/.local/share/applications"
mkdir -p "$launcher_app_dir" "$launcher_bin"
cp "$ROOT"/applications/*.desktop "$launcher_app_dir/"
cp "$ROOT/default/alacritty/Alacritty.desktop" "$launcher_app_dir/"
printf '[Desktop Entry]\nName=Child Journal\nType=Application\nExec=true\n' >"$launcher_app_dir/Child Journal.desktop"
printf '#!/bin/bash\nexit 0\n' >"$launcher_bin/update-desktop-database"
printf '#!/bin/bash\nexit 0\n' >"$launcher_bin/omarchy-cmd-present"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >>"$OMARCHY_TEST_MISE_CALLS"\n' >"$launcher_bin/omarchy-mise-install"
printf '#!/bin/bash\nexit 0\n' >"$launcher_bin/omarchy-install-hermes-cli"
printf '#!/bin/bash\n[[ ${STUB_PROFILE:-child} == child ]]\n' >"$launcher_bin/omarchy-profile-child"
printf '#!/bin/bash\nprintf "refresh\\n" >>"$OMARCHY_TEST_MIGRATION_CALLS"\n' >"$launcher_bin/omarchy-refresh-applications"
chmod +x "$launcher_bin"/*
mise_calls="$test_tmp/mise-calls"
: >"$mise_calls"
HOME="$launcher_home" PATH="$launcher_bin:$PATH" OMARCHY_PATH="$ROOT" OMARCHY_TEST_MISE_CALLS="$mise_calls" bash "$ROOT/bin/omarchy-refresh-applications" >/dev/null
entries=$(ls "$launcher_home/.local/share/applications" | LC_ALL=C sort | tr '\n' ' ')
[[ $entries == "Child Journal.desktop Google Maps.desktop Khan Academy.desktop Math Time.desktop Wikipedia.desktop imv.desktop mpv.desktop " ]] || fail "a child install prunes seeded Omarchy entries, keeps custom launchers, and adds the child set" "$entries"
[[ ! -s $mise_calls ]] || fail "a child install gets no agent CLI stubs" "$(<"$mise_calls")"
while IFS= read -r name; do
  name=${name%%#*}; name=${name%"${name##*[![:space:]]}"}
  [[ -z $name ]] || [[ -f "$ROOT/applications/$name.desktop" ]] || fail "the child applications list names a shipped entry: $name"
done <"$ROOT/install/omarchy-child.applications"
for f in "$ROOT"/applications/child/*.desktop; do
  grep -q -E '^Exec=(omarchy-launch-webapp https://|omarchy-shell shell summon omarchy\.)' "$f" && grep -q '^Icon=' "$f" || fail "a child-only entry is a web app or a shell app, with an icon: ${f##*/}"
done
rm -rf "$launcher_home/.local"
: >"$mise_calls"
HOME="$launcher_home" PATH="$launcher_bin:$PATH" STUB_PROFILE=default OMARCHY_PATH="$ROOT" OMARCHY_TEST_MISE_CALLS="$mise_calls" bash "$ROOT/bin/omarchy-refresh-applications" >/dev/null
[[ -f "$launcher_home/.local/share/applications/Discord.desktop" && -f "$launcher_home/.local/share/applications/Docker.desktop" && ! -f "$launcher_home/.local/share/applications/Khan Academy.desktop" ]] || fail "a Me install's launcher is unchanged"
grep -q '^claude$' "$mise_calls" || fail "a Me install keeps the agent CLI stubs" "$(<"$mise_calls")"
pass "a child install's launcher is the school-and-creativity set, without terminal or agent stubs"

migration_calls="$test_tmp/migration-calls"
: >"$migration_calls"
PATH="$launcher_bin:$PATH" OMARCHY_TEST_MIGRATION_CALLS="$migration_calls" bash -euo pipefail "$ROOT/migrations/1788415541.sh" >/dev/null
[[ $(<"$migration_calls") == refresh ]] || fail "the launcher repair runs for an existing child profile" "$(<"$migration_calls")"
: >"$migration_calls"
PATH="$launcher_bin:$PATH" STUB_PROFILE=default OMARCHY_TEST_MIGRATION_CALLS="$migration_calls" bash -euo pipefail "$ROOT/migrations/1788415541.sh" >/dev/null
[[ ! -s $migration_calls ]] || fail "the launcher repair leaves a Me profile alone" "$(<"$migration_calls")"
pass "existing child profiles refresh their launchers once after updating"

# The theme set: omarchy-theme-offered against a scratch tree.
fake="$test_tmp/omarchy"
mkdir -p "$fake/install" "$fake/themes/bubblegum" "$fake/themes/hackerman" "$test_tmp/home/.config/omarchy/themes/mine" "$test_tmp/bin"
printf '# child themes\nbubblegum\nnord  \n' >"$fake/install/omarchy-child.themes"
cat >"$test_tmp/bin/omarchy-profile-child" <<'SH'
#!/bin/bash
[[ ${STUB_PROFILE:-child} == child ]]
SH
chmod +x "$test_tmp/bin/omarchy-profile-child"
offered() {
  HOME="$test_tmp/home" OMARCHY_PATH="$fake" PATH="$test_tmp/bin:$PATH" bash "$ROOT/bin/omarchy-theme-offered" "$@"
}
offered bubblegum || fail "a listed theme is offered on a child install"
offered nord || fail "a listed theme is offered despite trailing spaces in the list"
! offered hackerman || fail "an unlisted theme is not offered on a child install"
offered mine || fail "the kid's own theme is always offered"
STUB_PROFILE=default offered hackerman || fail "a Me install offers every theme"
rm "$fake/install/omarchy-child.themes"
offered hackerman || fail "a child install without a list offers every theme"
! offered >/dev/null 2>&1 || fail "the predicate needs a theme name"
grep -q 'omarchy-theme-offered "$theme"' "$ROOT/bin/omarchy-theme-list" || fail "omarchy-theme-list asks the predicate"
[[ $(grep -c 'omarchy-theme-offered "$theme_name" || continue' "$ROOT/bin/omarchy-theme-switcher") == 2 ]] || fail "the theme switcher asks the predicate for user and shipped themes"
grep -q 'omarchy-child.themes' "$ROOT/bin/omarchy-theme-switcher" || fail "the switcher's preview cache keys on the child list"
pass "a child install offers the child-friendly themes and the kid's own"

# The default theme on a child install: the first name in the list.
mock="$test_tmp/mock"
mkdir -p "$mock" "$test_tmp/seed-home/.config/chromium" "$test_tmp/seed-home/.local/state/omarchy/current"
cat >"$mock/omarchy-theme-set" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_THEME_CALLS"
SH
printf '#!/bin/bash\nexit 0\n' >"$mock/omarchy-theme-set-pi"
cp "$test_tmp/bin/omarchy-profile-child" "$mock/omarchy-profile-child"
chmod +x "$mock"/*
calls="$test_tmp/theme-calls"
: >"$calls"
HOME="$test_tmp/seed-home" PATH="$mock:$PATH" OMARCHY_PATH="$ROOT" OMARCHY_TEST_THEME_CALLS="$calls" bash "$ROOT/install/user/theme.sh"
[[ $(<"$calls") == bubblegum ]] || fail "a child install starts on the first theme of the child list" "calls: $(<"$calls")"
: >"$calls"
HOME="$test_tmp/seed-home" PATH="$mock:$PATH" OMARCHY_PATH="$ROOT" OMARCHY_TEST_THEME_CALLS="$calls" STUB_PROFILE=default bash "$ROOT/install/user/theme.sh"
[[ $(<"$calls") == "Tokyo Night" ]] || fail "a Me install still starts on Tokyo Night" "calls: $(<"$calls")"
pass "a child install starts on the first child theme"

# The shipped list names real themes, and the placeholder is a whole theme.
while IFS= read -r name; do
  [[ -d $ROOT/themes/$name ]] || fail "child theme list names a theme that ships: $name"
done < <(grep -v '^#' "$ROOT/install/omarchy-child.themes" | sed -e '/^[[:space:]]*$/d')
[[ $(grep -v '^#' "$ROOT/install/omarchy-child.themes" | sed -e '/^[[:space:]]*$/d' | head -n 1) == bubblegum ]] || fail "the placeholder theme leads the child list"
theme="$ROOT/themes/bubblegum"
grep -qx 'mode = "light"' "$theme/colors.toml" || fail "the placeholder is a light theme"
for key in accent selection muted background dark_background darker_background lighter_background foreground dark_foreground light_foreground bright_foreground red yellow orange green cyan blue magenta brown bright_red bright_yellow bright_green bright_cyan bright_blue bright_magenta; do
  grep -q "^$key = \"#[0-9a-f]\{6\}\"$" "$theme/colors.toml" || fail "the placeholder defines $key"
done
[[ -n $(find "$theme/backgrounds" -maxdepth 1 -type f \( -iname '*.webp' -o -iname '*.png' -o -iname '*.jpg' \) | head -n 1) ]] || fail "the placeholder ships a background, which the switcher previews"
[[ -s $theme/icons.theme && -s $theme/keyboard.rgb && -s $theme/neovim.lua && -s $theme/vscode.json ]] || fail "the placeholder carries icons, keyboard, editor, and VS Code settings"
pass "the child theme list names shipped themes and the placeholder theme is complete"

# The boot screen: the placeholder ships the assets Style > Unlock and the
# install leaf need, and the leaf applies the first child theme on child
# installs only, without ever failing the install.
[[ -f $theme/unlock.png && -f $theme/preview-unlock.png ]] || fail "the placeholder ships a boot wordmark and an unlock preview"
python3 - "$theme" <<'PY' || fail "the boot assets have the packaged geometry"
from PIL import Image
import sys
t = sys.argv[1]
assert Image.open(t + "/unlock.png").size == Image.open("default/plymouth/logo.png").size, "unlock.png matches the packaged logo"
assert Image.open(t + "/preview-unlock.png").size == (1920, 1080), "preview-unlock.png is 1920x1080"
PY
grep -qx 'run_logged "$OMARCHY_INSTALL/config/plymouth.sh"' "$ROOT/install/config/all.sh" || fail "the install runs the boot screen leaf"
leaf_bin="$test_tmp/leafbin"
mkdir -p "$leaf_bin"
cp "$test_tmp/bin/omarchy-profile-child" "$leaf_bin/omarchy-profile-child"
cat >"$leaf_bin/omarchy-plymouth-set-by-theme" <<'SH'
#!/bin/bash
printf 'plymouth %s\n' "$*" >>"$LEAF_CALLS"
exit "${STUB_PLYMOUTH_STATUS:-0}"
SH
chmod +x "$leaf_bin"/*
export LEAF_CALLS="$test_tmp/leaf-calls"
: >"$LEAF_CALLS"
PATH="$leaf_bin:$PATH" OMARCHY_PATH="$ROOT" STUB_PROFILE=default bash -e "$ROOT/install/config/plymouth.sh"
[[ ! -s $LEAF_CALLS ]] || fail "a Me install keeps the packaged boot screen"
PATH="$leaf_bin:$PATH" OMARCHY_PATH="$ROOT" STUB_PROFILE=child bash -e "$ROOT/install/config/plymouth.sh"
[[ $(<"$LEAF_CALLS") == "plymouth bubblegum" ]] || fail "a child install applies the first child theme to the boot screen" "$(<"$LEAF_CALLS")"
PATH="$leaf_bin:$PATH" OMARCHY_PATH="$ROOT" STUB_PROFILE=child STUB_PLYMOUTH_STATUS=1 bash -e "$ROOT/install/config/plymouth.sh" >/dev/null || fail "a boot screen that cannot be set does not fail the install"
pass "a child install boots in its theme's colours, and cannot fail on it"

# The wordmark in a terminal and on the first-boot screens: the theme's
# accent on a child install, Omarchy green elsewhere.
logo_bin="$test_tmp/logo-bin"
mkdir -p "$logo_bin"
printf '#!/bin/bash\nexit 0\n' >"$logo_bin/clear"
printf '#!/bin/bash\n[[ ${STUB_PROFILE:-child} == child ]]\n' >"$logo_bin/omarchy-profile-child"
printf '#!/bin/bash\necho "#d6336c"\n' >"$logo_bin/omarchy-theme-color"
printf '#!/bin/bash\necho /dev/tty1\n' >"$logo_bin/tty"
chmod +x "$logo_bin"/*
shown=$(PATH="$logo_bin:$PATH" OMARCHY_PATH="$ROOT" bash "$ROOT/bin/omarchy-show-logo")
[[ $shown == *$'\033[38;2;214;51;108m'* && $shown == *"$(head -n 1 "$ROOT/logo.txt")"* ]] || fail "a child install's terminal wordmark is the theme's accent" "$(printf '%q' "$shown" | cut -c1-80)"
shown=$(PATH="$logo_bin:$PATH" OMARCHY_PATH="$ROOT" STUB_PROFILE=default bash "$ROOT/bin/omarchy-show-logo")
[[ $shown == *$'\033[32m'* && $shown != *'38;2;'* ]] || fail "a Me install's terminal wordmark stays green"
paint=$(sed -n '/^paint_logo_color() {/,/^}/p' "$ROOT/bin/omarchy-provision-owner")
[[ -n $paint ]] || fail "first-boot provisioning paints the console's logo colour"
grep -q '^  paint_logo_color$' "$ROOT/bin/omarchy-provision-owner" || fail "the first-boot logo is painted before it is drawn"
painted=$(PATH="$logo_bin:$PATH" OMARCHY_PATH="$ROOT" CHILD_INSTALL=true bash -c "$paint; paint_logo_color" | od -An -c | tr -s ' ' | tr -d '\n')
[[ $painted == *'033 ] P 2 d 6 3 3 6 c'* ]] || fail "a child install's first boot repaints console green as the theme's accent" "$painted"
[[ -z $(PATH="$logo_bin:$PATH" OMARCHY_PATH="$ROOT" CHILD_INSTALL=false bash -c "$paint; paint_logo_color") ]] || fail "a Me install's first boot leaves the console palette alone"
printf '#!/bin/bash\necho /dev/pts/3\n' >"$logo_bin/tty"
[[ -z $(PATH="$logo_bin:$PATH" OMARCHY_PATH="$ROOT" CHILD_INSTALL=true bash -c "$paint; paint_logo_color") ]] || fail "the console escape is sent to a console only"
pass "the wordmark wears the theme's accent in a child install's terminals and at first boot"
