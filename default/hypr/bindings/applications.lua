-- Essential application bindings.
o.bind("SUPER + RETURN", "Terminal", { omarchy = "terminal" })
o.bind("SUPER + SHIFT + RETURN", "Browser", { omarchy = "browser" })
o.bind("SUPER + SHIFT + F", "File manager", { omarchy = "nautilus" })
o.bind("SUPER + ALT + SHIFT + F", "File manager (cwd)", { omarchy = "nautilus-cwd" })
o.bind("SUPER + SHIFT + B", "Browser", { omarchy = "browser" })
o.bind("SUPER + SHIFT + ALT + B", "Browser (private)", { omarchy = "browser --private" })
o.bind("SUPER + SHIFT + N", "Editor", { omarchy = "editor" })

if o.preinstalled_bindings_enabled() then
  -- Bindings for preinstalled Omarchy applications, TUIs, and web apps. A
  -- child install (kids mode) keeps the ones a kid can use and leaves the
  -- work, chat, social, and AI ones out, along with YouTube, which a kid
  -- reaches through a supervised account in the browser rather than an
  -- unrestricted shortcut; it gets a couple of places to learn instead. See
  -- plans/kids-apps-themes.md.
  local kid = o.child_install()

  if not kid then
    o.bind("SUPER + ALT + RETURN", "Tmux", { omarchy = "terminal-tmux" })
    o.bind("SUPER + CTRL + RETURN", "Herdr", { omarchy = "terminal-herdr" })
  end
  if kid then
    o.bind("SUPER + SHIFT + M", "Music", { tui = "cliamp", focus = true })
  else
    o.bind("SUPER + SHIFT + M", "Music", { omarchy = "spotify" })
    o.bind("SUPER + SHIFT + ALT + M", "Music TUI", { tui = "cliamp", focus = true })
  end
  if not kid then
    o.bind("SUPER + SHIFT + D", "Docker", { tui = "omarchy-launch-docker-tui" })
    o.bind("SUPER + SHIFT + G", "Signal", { omarchy = "signal" })
  end
  o.bind("SUPER + SHIFT + O", "Obsidian", { launch = "obsidian", focus = "^obsidian$" })
  o.bind("SUPER + SHIFT + W", "Omawrite", { launch = "omawrite" })
  if not kid then
    o.bind("SUPER + SHIFT + SLASH", "Passwords", { omarchy = "1password" })

    o.bind("SUPER + SHIFT + A", "ChatGPT", { webapp = "https://chatgpt.com" })
    o.bind("SUPER + SHIFT + ALT + A", "Grok", { webapp = "https://grok.com" })
    o.bind("SUPER + SHIFT + C", "Calendar", { webapp = "https://app.hey.com/calendar/weeks/" })
    o.bind("SUPER + SHIFT + E", "Email", { webapp = "https://app.hey.com" })
    o.bind("SUPER + SHIFT + ALT + E", "New email", { webapp = "https://app.hey.com/messages/new?display=standalone&new_window=true" })
  end
  if not kid then
    o.bind("SUPER + SHIFT + Y", "YouTube", { webapp = "https://youtube.com/" })
    o.bind("SUPER + SHIFT + ALT + G", "WhatsApp", { webapp = "https://web.whatsapp.com/", focus = true })
    o.bind( "SUPER + SHIFT + CTRL + G", "Google Messages", { webapp = "https://messages.google.com/web/conversations", focus = true })
    o.bind("SUPER + SHIFT + P", "Google Photos", { webapp = "https://photos.google.com/", focus = true })
  end
  o.bind("SUPER + SHIFT + S", "Google Maps", { webapp = "https://maps.google.com/", focus = true })
  if kid then
    o.bind("SUPER + SHIFT + K", "Khan Academy", { webapp = "https://www.khanacademy.org/" })
    o.bind("SUPER + SHIFT + ALT + K", "Wikipedia", { webapp = "https://www.wikipedia.org/" })
  else
    o.bind("SUPER + SHIFT + X", "X", { webapp = "https://x.com/" })
    o.bind("SUPER + SHIFT + ALT + X", "X Post", { webapp = "https://x.com/compose/post" })
  end
end
