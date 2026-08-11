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
-- Window Routing Rules
-- ============================================================================

-- Helper to create silent workspace routing rules
local function route_to_workspace(name, workspace, match)
	hl.window_rule({
		name = name,
		match = match,
		workspace = workspace .. " silent",
	})
end

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
route_to_workspace("steam-gaming-workspace", WORKSPACE.gaming, {
	class = "^(steam|Steam|com[.]valvesoftware[.]Steam)$",
})
route_to_workspace("lutris-gaming-workspace", WORKSPACE.gaming, {
	class = "^(lutris|net[.]lutris[.]Lutris)$",
})
route_to_workspace("game-content-workspace", WORKSPACE.gaming, {
	content = "game",
})
route_to_workspace("steam-game-workspace", WORKSPACE.gaming, {
	class = "^steam_app_[0-9]+$",
})

-- Media workspace: 10
route_to_workspace("mpv-media-workspace", WORKSPACE.media, { class = "^mpv$" })
route_to_workspace("strawberry-media-workspace", WORKSPACE.media, {
	class = "^(strawberry|org[.]strawberrymusicplayer[.]strawberry)$",
})

-- ============================================================================
-- Editor Workspace: 4 (Godot Custom Layout)
-- ============================================================================

-- Encapsulate the entire layout setup to keep the global scope clean
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

setup_godot_layout()
