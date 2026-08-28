require("config.options")
require("config.keymaps")
require("config.autocmds")
require("config.lsp")

-- Load all plugin configs
local plugin_modules = {
	"harpoon",
	"conform",
	"lint",
	"snacks",
	"dap",
	"neotest",
	"goose",
}

for _, mod in ipairs(plugin_modules) do
	local ok, err = pcall(require, "plugins." .. mod)
	if not ok then
		vim.notify("Failed to load plugin: " .. mod .. "\n" .. err, vim.log.levels.WARN)
	end
end
