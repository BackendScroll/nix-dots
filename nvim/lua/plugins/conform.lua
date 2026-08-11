local utils = require("config.env")
local env_formatters = utils.parse_json_env("NVIM_FORMATTERS")

-- Global formatters available everywhere
local default_formatters = {
	nix = { "alejandra" },
	lua = { "stylua" },
}

-- Merge project-specific formatters over defaults
local formatters_by_ft = vim.tbl_deep_extend("force", default_formatters, env_formatters)

require("conform").setup({
	formatters_by_ft = formatters_by_ft,
	format_on_save = {
		timeout_ms = 500,
		lsp_fallback = true,
	},
})

vim.keymap.set({ "n", "v" }, "<leader>cf", function()
	require("conform").format({ lsp_fallback = true })
end, { desc = "Format Code" })
