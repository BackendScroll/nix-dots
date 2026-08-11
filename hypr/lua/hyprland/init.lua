hl.env("qsConfig", "ii")

terminal = "ghostty"
fileManager = "dolphin"
browser = "zen-twilight"
menu = "fuzzel"
codeEditor = "nvim"
officeSoftware = "onlyoffice-desktopeditors"
textEditor = terminal .. " e nvim"
volumeMixer = "pavucontrol-qt"
settingsApp = "qs -p ~/.config/quickshell/$qsConfig/settings.qml || systemsettings"
taskManager = terminal .. " -e fish -c btop"

workspaceGroupSize = 10

require("hyprland.lib")
require("hyprland.services")

require("hyprland.env")
require("hyprland.autostart")
require("hyprland.rules")
require("hyprland.colors")
require("hyprland.keybinds")
require("hyprland.monitors")
require("hyprland.gestures")
require("hyprland.animations")
require("hyprland.decorations")
require("hyprland.layout")

-- Custom configurations --
require("custom.general")
require("custom.rules")
require("custom.keybinds")
require("custom.monitors")
require("custom.workspaces")

-- Shell overrides --
require("hyprland.shellOverrides.main")
