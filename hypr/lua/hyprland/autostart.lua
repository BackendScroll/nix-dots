-- Compositor-specific one-shot actions only.
--
-- Persistent session processes (QuickShell, GNOME Keyring, EasyEffects and the
-- cliphist watchers) are systemd user services owned by Home Manager. See
-- home/dirkk/desktop/services.nix and home/dirkk/quickshell/quickshell.nix.
hl.on("hyprland.start", function()
	-- Hand the compositor's Wayland environment to the session bus so systemd
	-- user units started after this point inherit a usable display.
	hl.exec_cmd("dbus-update-activation-environment --systemd --all")

	hl.exec_cmd("hyprctl setcursor Bibata-Modern-Classic 24")
end)
