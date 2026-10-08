hl.layer_rule({ match = { namespace = "quickshell" }, blur = true })
hl.layer_rule({ match = { namespace = "quickshell" }, blur_popups = true })
hl.layer_rule({ match = { namespace = "quickshell" }, ignore_alpha = 0.1 })

hl.layer_rule({ match = { namespace = "selection" }, animation = "fade" })
hl.layer_rule({ match = { namespace = "user-panel" }, animation = "fade" })
hl.layer_rule({ match = { namespace = "hyprpicker" }, animation = "fade" })
hl.layer_rule({ match = { namespace = "app-launcher" }, animation = "fade" })

-- Desktop widgets (desktop-widgets): blur behind their menus and glass cards like
-- the shell's panels. ignore_alpha keeps the clear desktop and thin text unblurred.
hl.layer_rule({ match = { namespace = "desktop-widgets" }, blur = true })
hl.layer_rule({ match = { namespace = "desktop-widgets" }, ignore_alpha = 0.5 })
