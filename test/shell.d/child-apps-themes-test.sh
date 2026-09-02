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
for gone in "X" "X Post" "ChatGPT" "Grok" "WhatsApp" "Google Messages" "Email" "Calendar" "Signal" "Docker" "Passwords"; do
  ! grep -q $'\t'"$gone"'$' <<<"$kid" || fail "a child install has no $gone binding"
  grep -q $'\t'"$gone"'$' <<<"$grown" || fail "a Me install keeps the $gone binding"
done
for kept in "Browser" "File manager" "YouTube" "Google Photos" "Google Maps" "Music" "Obsidian"; do
  grep -q $'\t'"$kept"'$' <<<"$kid" || fail "a child install keeps the $kept binding"
done
grep -q $'^SUPER + SHIFT + K\tKhan Academy$' <<<"$kid" && grep -q $'^SUPER + SHIFT + ALT + K\tWikipedia$' <<<"$kid" || fail "a child install gets Khan Academy and Wikipedia"
! grep -q 'Khan Academy\|Wikipedia' <<<"$grown" || fail "a Me install is unchanged"
[[ $(cut -f1 <<<"$kid" | sort | uniq -d) == "" ]] || fail "the child bindings do not collide" "$(cut -f1 <<<"$kid" | sort | uniq -d)"
pass "a child install's app bindings leave out the grown-up web apps and add places to learn"

grep -q '"learn.community": {[^}]*"when":"! omarchy-profile-child"' "$ROOT/default/omarchy/omarchy-menu.jsonc" || fail "the Discord community link stays off a child install's menu"
pass "the menu keeps the Discord link off a child install"

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
