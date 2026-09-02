# Setup user theme folder and seed the default only when no theme exists yet.
mkdir -p ~/.config/omarchy/themes

if [[ ! -s $HOME/.local/state/omarchy/current/theme.name ]]; then
  # A child install (kids mode) starts on the first theme of its list.
  default_theme="Tokyo Night"
  if omarchy-profile-child 2>/dev/null; then
    child_theme=$(grep -v '^#' "$OMARCHY_PATH/install/omarchy-child.themes" 2>/dev/null | sed -e 's/[[:space:]]*$//' -e '/^$/d' | head -n 1)
    [[ -n $child_theme ]] && default_theme=$child_theme
  fi

  # iso-chroot and provision-owner both run without a live session to notify.
  if [[ ${OMARCHY_SETUP_CONTEXT:-runtime} != "runtime" ]]; then
    OMARCHY_THEME_HEADLESS=1 omarchy-theme-set "$default_theme"
    rm -f ~/.config/chromium/SingletonLock # otherwise archiso owns the Chromium singleton
  else
    omarchy-theme-set "$default_theme"
  fi
fi
omarchy-theme-set-pi --activate

mkdir -p ~/.config/btop/themes
ln -snf "$HOME/.local/state/omarchy/current/theme/btop.theme" ~/.config/btop/themes/current.theme
