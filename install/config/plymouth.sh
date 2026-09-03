# A child install boots in its theme's colours from the first start: the boot
# splash and the login screen take the first child theme's background, text
# colour, and wordmark, the way Style > Unlock would. omarchy-plymouth-set
# runs as root here because the target chroot is where the installer sits,
# and it leaves the initramfs to the installer. A "Me" install keeps the
# packaged boot screen. Nothing here may fail the install: a boot screen in
# the wrong colours is a cosmetic miss.
if omarchy-profile-child; then
  child_theme=$(grep -v '^#' "$OMARCHY_PATH/install/omarchy-child.themes" 2>/dev/null | sed -e 's/[[:space:]]*$//' -e '/^$/d' | head -n 1)
  if [[ -n $child_theme ]]; then
    if ! omarchy-plymouth-set-by-theme "$child_theme"; then
      echo "Boot screen left as packaged: omarchy-plymouth-set-by-theme $child_theme did not succeed."
    fi
  fi
fi
