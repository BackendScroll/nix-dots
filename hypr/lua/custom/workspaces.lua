-- ============================================================================
-- Workspace & Window Rule Configuration (workspace.lua)
-- Targets the Hyprland >= 0.55 Lua config API.
-- ============================================================================

-- ============================================================================
-- Workspace Map
-- ============================================================================

local WORKSPACE = {
	overview = "1",
	programming = "3",
	editor = "4",
	graphics = "6",
	books = "7",
	gaming = "9",
	media = "10",
}

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- hl.window_rule takes props inside `match` and effects as plain top-level
-- fields. There is no `rule` field, and no need for one rule per effect:
-- a single call carries as many effects as you want.
local function window_rule(name, match, effects)
	local rule = { name = name, match = match }
	for key, value in pairs(effects or {}) do
		rule[key] = value
	end
	hl.window_rule(rule)
end

-- Route windows silently to a specific workspace.
local function route_to_workspace(name, workspace, match)
	window_rule(name, match, { workspace = workspace .. " silent" })
end

-- Merge tables into a fresh one, so shared effect presets are never mutated.
local function merge(...)
	local result = {}
	for _, source in ipairs({ ... }) do
		for key, value in pairs(source) do
			result[key] = value
		end
	end
	return result
end

-- ============================================================================
-- Gaming Window Matches
-- ============================================================================

-- gamescope: the ONLY window Hyprland sees when a game is wrapped by it. The
-- game's own window lives inside gamescope's nested compositor and never
-- appears in `hyprctl clients`.
local MATCH_GAMESCOPE = { class = "^gamescope.*$" }

-- Bare (unwrapped) games. Civ5 reports class `Civ5XP` under XWayland, NOT
-- `steam_app_8930`, so it needs its own match.
local MATCH_CIV5 = { class = "^Civ5XP$" }
local MATCH_STEAM_GAME = { class = "^steam_app_[0-9]+$" }

-- ============================================================================
-- Gaming Window Rules
-- ============================================================================

-- Effects shared by every game window, wrapped or not.
--
--   sync_fullscreen  THE key one for Civ5. When on (the default), Hyprland
--                    keeps its internal fullscreen state in sync with the
--                    client's. Civ5 reports fullscreenClient: 0 forever, so
--                    every workspace change drags internal fullscreen back
--                    down to 0 to match. Turning sync off lets the rule's
--                    fullscreen stand on its own.
--   suppress_event   `fullscreen` is deliberately NOT in this list: it also
--                    suppresses the rule's own fullscreen effect, so the
--                    window never goes fullscreen at all.
--   render_unfocused keeps frame callbacks flowing when the workspace is
--                    hidden. Pair with misc.render_unfocused_fps.
--   no_anim          the Lua field for the old `noanim`. Workspace-switch
--                    animations resize the window, and XWayland forwards
--                    those resizes to the client.
--
-- Deliberately NOT included: stay_focused. It pins focus to the window and
-- then fights the compositor on every workspace change.
local GAME_EFFECTS = {
	fullscreen = true,
	sync_fullscreen = false,
	suppress_event = "maximize activate activatefocus",
	render_unfocused = true,
	no_anim = true,
	idle_inhibit = "always",
}

-- FALLBACK, if sync_fullscreen alone is not enough. Sets internal and client
-- fullscreen explicitly (0=none, 1=maximize, 2=fullscreen, 3=both), telling
-- Civ5 it IS fullscreen so it stops trying to correct itself. Swap this in
-- for `fullscreen = true` above rather than using both.
--
--     fullscreen_state = "2 2",

-- Send game windows to the gaming workspace in the same rule.
local GAME_ROUTE = { workspace = WORKSPACE.gaming .. " silent" }

-- Tearing. Requires `general.allow_tearing = true` globally or it is inert.
local TEARING_EFFECTS = { immediate = true }

window_rule("gamescope-game", MATCH_GAMESCOPE, merge(GAME_EFFECTS, GAME_ROUTE, TEARING_EFFECTS))

window_rule("civ5-game", MATCH_CIV5, merge(GAME_EFFECTS, GAME_ROUTE))

window_rule("steam-app-game", MATCH_STEAM_GAME, merge(GAME_EFFECTS, GAME_ROUTE))

-- ============================================================================
-- Fullscreen Watchdog (last resort)
-- ============================================================================

-- Only enable this if the window rules above still lose fullscreen. It
-- re-asserts fullscreen from Lua whenever the compositor drops it. Costs a
-- dispatch per event, so leave it off unless you need it.
local FULLSCREEN_WATCHDOG = false

local WATCHED_GAME_CLASSES = {
	"^Civ5XP$",
	"^gamescope.*$",
	"^steam_app_[0-9]+$",
}

local function is_watched_game(win)
	if not win or not win.class then
		return false
	end
	for _, pattern in ipairs(WATCHED_GAME_CLASSES) do
		if win.class:match(pattern) then
			return true
		end
	end
	return false
end

local function reassert_fullscreen(win)
	if not is_watched_game(win) or win.fullscreen ~= 0 then
		return
	end
	-- Deferred: dispatching inside the event handler risks re-entrancy, and
	-- event callbacks run under a ~50ms guarded call.
	hl.timer(function()
		if win.fullscreen == 0 then
			hl.dispatch(hl.dsp.window.fullscreen({
				mode = "fullscreen",
				action = "set",
				window = win,
			}))
		end
	end, { timeout = 60, type = "oneshot" })
end

if FULLSCREEN_WATCHDOG then
	hl.on("window.fullscreen", reassert_fullscreen)

	hl.on("workspace.active", function(workspace)
		for _, win in ipairs(workspace:get_windows()) do
			reassert_fullscreen(win)
		end
	end)
end

-- ============================================================================
-- Window Routing Rules
-- ============================================================================

-- Overview workspace: 1
route_to_workspace("obsidian-overview-workspace", WORKSPACE.overview, {
	class = "^obsidian$",
	initial_title = "^AeternumStrategion - Obsidian.*$",
})

-- Programming workspace: 3
-- route_to_workspace("terminal-programming-workspace", WORKSPACE.programming, { class = "^Alacritty$" })
-- route_to_workspace("ide-programming-workspace", WORKSPACE.programming, { class = "^jetbrains-.+$" })

-- Graphics workspace: 6
route_to_workspace("blender-graphics-workspace", WORKSPACE.graphics, { class = "^Blender$" })
route_to_workspace("gimp-graphics-workspace", WORKSPACE.graphics, { class = "^Gimp$" })

-- Books workspace: 7
route_to_workspace("calibre-books-workspace", WORKSPACE.books, {
	class = "^(calibre-gui|com[.]calibre_ebook[.]calibre)$",
})

-- Gaming workspace: 9
-- The game windows themselves are routed above, together with their effects.
route_to_workspace("steam-gaming-workspace", WORKSPACE.gaming, {
	class = "^(steam|Steam|com[.]valvesoftware[.]Steam)$",
})
route_to_workspace("lutris-gaming-workspace", WORKSPACE.gaming, {
	class = "^(lutris|net[.]lutris[.]Lutris)$",
})

-- Kept as a catch-all, but note it did not match Civ5: that window reports
-- `contentType: none`, not `game`.
route_to_workspace("game-content-workspace", WORKSPACE.gaming, {
	content = "game",
})

-- Media workspace: 10
route_to_workspace("mpv-media-workspace", WORKSPACE.media, { class = "^mpv$" })
route_to_workspace("strawberry-media-workspace", WORKSPACE.media, {
	class = "^(strawberry|org[.]strawberrymusicplayer[.]strawberry)$",
})

-- ============================================================================
-- Editor Workspace: 4 (Godot Custom Layout)
-- ============================================================================

local function setup_godot_layout()
	local CONFIG = {
		layout_name = "godot-workspace",
		editor_class = "org.godotengine.Editor",
		project_manager_class = "org.godotengine.ProjectManager",
		console_title = "Godot Console",

		default_godot_ratio = 0.50,
		minimum_godot_ratio = 0.20,
		maximum_godot_ratio = 0.85,

		default_console_ratio = 0.25,
		minimum_console_ratio = 0.15,
		maximum_console_ratio = 0.60,

		resize_step = 0.05,
	}

	local RATIO_AXES = {
		godot = {
			key = "godot_ratio",
			default = CONFIG.default_godot_ratio,
			minimum = CONFIG.minimum_godot_ratio,
			maximum = CONFIG.maximum_godot_ratio,
		},
		console = {
			key = "console_ratio",
			default = CONFIG.default_console_ratio,
			minimum = CONFIG.minimum_console_ratio,
			maximum = CONFIG.maximum_console_ratio,
		},
	}

	local state = {
		console_ratio = CONFIG.default_console_ratio,
		godot_ratio = CONFIG.default_godot_ratio,
	}

	-- Utilities
	local function clamp(value, minimum, maximum)
		return math.max(minimum, math.min(maximum, value))
	end

	local function set_ratio(axis, value)
		state[axis.key] = clamp(value, axis.minimum, axis.maximum)
	end

	local function adjust_ratio(axis, fraction)
		-- NaN check (fraction ~= fraction is true only if fraction is NaN)
		if fraction ~= fraction or fraction == 0 then
			return
		end
		set_ratio(axis, state[axis.key] + fraction)
	end

	-- Target matching
	local function get_window(target)
		return target and target.window or nil
	end

	local function target_has_class(target, class)
		local win = get_window(target)
		return win ~= nil and win.class == class
	end

	local function is_godot_editor(target)
		return target_has_class(target, CONFIG.editor_class)
	end

	local function is_godot_project_manager(target)
		return target_has_class(target, CONFIG.project_manager_class)
	end

	local function is_godot_console(target)
		local win = get_window(target)
		return win ~= nil and win.initial_title == CONFIG.console_title
	end

	local function same_target(a, b)
		if not a or not b then
			return false
		end
		if a == b then
			return true
		end
		local win_a = get_window(a)
		return win_a ~= nil and win_a == get_window(b)
	end

	-- Area geometry
	local function split_pair(ctx, area, is_horizontal, ratio)
		if is_horizontal then
			return ctx:split(area, "left", ratio), ctx:split(area, "right", 1 - ratio)
		end
		return ctx:split(area, "top", ratio), ctx:split(area, "bottom", 1 - ratio)
	end

	local function tile_balanced(ctx, targets, area, first, last, is_horizontal)
		first = first or 1
		last = last or #targets

		if first > last then
			return
		end

		if first == last then
			targets[first]:place(area)
			return
		end

		local count = last - first + 1
		local first_count = math.ceil(count / 2)
		local midpoint = first + first_count - 1
		local ratio = first_count / count

		local area_a, area_b = split_pair(ctx, area, is_horizontal, ratio)

		tile_balanced(ctx, targets, area_a, first, midpoint, not is_horizontal)
		tile_balanced(ctx, targets, area_b, midpoint + 1, last, not is_horizontal)
	end

	local function tile_godot_pane(ctx, main, console, area)
		if main and console then
			local editor_ratio = 1 - state.console_ratio
			local editor_area, console_area = split_pair(ctx, area, false, editor_ratio)
			main:place(editor_area)
			console:place(console_area)
		elseif main then
			main:place(area)
		elseif console then
			console:place(area)
		end
	end

	local function collect_targets(targets)
		local editor, pm, console, ordinary
		ordinary = {}

		for _, target in ipairs(targets) do
			if not editor and is_godot_editor(target) then
				editor = target
			elseif not pm and is_godot_project_manager(target) then
				pm = target
			elseif not console and is_godot_console(target) then
				console = target
			else
				table.insert(ordinary, target)
			end
		end

		if editor and pm then
			table.insert(ordinary, pm)
		end

		return editor or pm, console, ordinary
	end

	local function recalculate(ctx)
		local main, console, ordinary = collect_targets(ctx.targets)

		if not main and not console then
			tile_balanced(ctx, ordinary, ctx.area, 1, #ordinary, true)
			return
		end

		if #ordinary == 0 then
			tile_godot_pane(ctx, main, console, ctx.area)
			return
		end

		local ordinary_area, godot_area = split_pair(ctx, ctx.area, true, 1 - state.godot_ratio)
		tile_balanced(ctx, ordinary, ordinary_area, 1, #ordinary, true)
		tile_godot_pane(ctx, main, console, godot_area)
	end

	local function handle_message(_, message)
		local command, argument = message:match("^%s*(%S+)%s*(.-)%s*$")
		if not command then
			return "godot-workspace layout messages cannot be empty"
		end

		if command == "reset" then
			for _, axis in pairs(RATIO_AXES) do
				set_ratio(axis, axis.default)
			end
			return true
		end

		local name, verb = command:match("^(%a+)%-(%a+)$")
		local axis = name and RATIO_AXES[name]

		if not axis then
			return "unsupported godot-workspace layout message: " .. command
		end

		if verb == "grow" then
			set_ratio(axis, state[axis.key] + CONFIG.resize_step)
		elseif verb == "shrink" then
			set_ratio(axis, state[axis.key] - CONFIG.resize_step)
		elseif verb == "reset" then
			set_ratio(axis, axis.default)
		elseif verb == "set" then
			local ratio = tonumber(argument)
			if not ratio then
				return string.format(
					"%s-set expects a decimal ratio, for example: %s-set %.2f",
					name,
					name,
					axis.default
				)
			end
			set_ratio(axis, ratio)
		else
			return "unsupported godot-workspace layout message: " .. command
		end

		return true
	end

	local function resize(ctx, target, delta)
		local width = ctx.area.width
		local height = ctx.area.height

		if not width or width <= 0 or not height or height <= 0 then
			return
		end

		local main, console, ordinary = collect_targets(ctx.targets)

		if same_target(target, console) then
			adjust_ratio(RATIO_AXES.console, delta.y / height)
			if #ordinary > 0 then
				adjust_ratio(RATIO_AXES.godot, delta.x / width)
			end
		elseif same_target(target, main) then
			if console then
				adjust_ratio(RATIO_AXES.console, -delta.y / height)
			end
			if #ordinary > 0 then
				adjust_ratio(RATIO_AXES.godot, delta.x / width)
			end
		elseif main or console then
			adjust_ratio(RATIO_AXES.godot, -delta.x / width)
		end
	end

	hl.layout.register(CONFIG.layout_name, {
		recalculate = recalculate,
		layout_msg = handle_message,
		resize = resize,
	})

	hl.workspace_rule({
		workspace = WORKSPACE.editor,
		layout = "lua:" .. CONFIG.layout_name,
	})

	route_to_workspace("godot-main-workspace", WORKSPACE.editor, {
		class = "^org[.]godotengine[.](ProjectManager|Editor)$",
	})

	route_to_workspace("godot-console-workspace", WORKSPACE.editor, {
		initial_title = "^Godot Console$",
	})
end

-- ============================================================================
-- Initialize Custom Layouts
-- ============================================================================

setup_godot_layout()
