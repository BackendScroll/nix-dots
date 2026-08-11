local utils = require("config.env")
local lint = require("lint")

local default_linters = {
	nix = { "statix", "deadnix" },
	lua = { "luacheck" },
}

-- Merge project-specific linters over defaults
local env_linters = utils.parse_json_env("NVIM_LINTERS")
local linters_by_ft = vim.tbl_deep_extend("force", default_linters, env_linters)

-- Filter out linters whose executables are not currently in PATH
-- This prevents the ENOENT error spam if a tool is missing from the active environment
for ft, names in pairs(linters_by_ft) do
	local available = {}
	for _, name in ipairs(names) do
		local cmd = name
		-- Look up the actual executable name from nvim-lint's definitions if it exists
		if lint.linters[name] and lint.linters[name].cmd then
			cmd = lint.linters[name].cmd
		end

		if vim.fn.executable(cmd) == 1 then
			table.insert(available, name)
		end
	end
	linters_by_ft[ft] = available
end

lint.linters_by_ft = linters_by_ft

-- Autocommand to lint on events
vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
	callback = function()
		lint.try_lint()
	end,
})

-- Optional: Manual lint keymap
vim.keymap.set("n", "<leader>cl", function()
	lint.try_lint()
end, { desc = "Lint Code" })
