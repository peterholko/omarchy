# A child install (kids mode) carries the screen-time pill on its bar from the
# first login. It hides itself until a parent turns screen time on, so the
# bar of a fresh install looks the same; the edit is the kid's own shell
# config, made the way `omarchy bar put` makes it, without needing the shell
# to be running.
if omarchy-profile-child 2>/dev/null; then
  (
    source "$OMARCHY_PATH/bin/omarchy-shell-config"
    commit "$NORMALIZE | if any(.bar.layout[][]; (if type == \"object\" then .id else . end) == \"omarchy.screen-time\") then . else .bar.layout.right = [{\"id\": \"omarchy.screen-time\"}] + .bar.layout.right end"
  ) || echo "Could not put the screen-time pill on the bar; run: omarchy bar put omarchy.screen-time --section right" >&2
fi
