local home_dir = os.getenv("HOME")
os.execute("export QT_IMAGEIO_MAXALLOC=1073741824")

-- Wayland
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Applications
local xdg_data_dirs_old = os.getenv("XDG_DATA_DIRS") or ""
hl.env(
	"XDG_DATA_DIRS",
	home_dir
		.. "/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share:"
		.. xdg_data_dirs_old
)

-- Themes
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("XDG_MENU_PREFIX", "plasma-")

-- ILLOGICAL_IMPULSE_PYTHON is exported by Home Manager (see
-- home/dirkk/quickshell/quickshell.nix). Do not set it here.

-- Cursor
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
