echo "Remove non-child launchers from child profiles"

if omarchy-profile-child; then
  omarchy-refresh-applications
fi
