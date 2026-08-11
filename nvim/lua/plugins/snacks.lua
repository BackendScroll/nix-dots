require("snacks").setup({
	terminal = {
		win = {
			position = "float",
			border = "rounded",
		},
	},
})

local function run_env_cmd(env_var)
	local cmd = vim.env[env_var]
	if not cmd or cmd == "" then
		vim.notify(string.format("%s is not set in devenv", env_var), vim.log.levels.WARN)
		return
	end
	Snacks.terminal(cmd, { interactive = true })
end

vim.keymap.set("n", "<leader>cb", function()
	run_env_cmd("NVIM_BUILD_CMD")
end, { desc = "Build Project" })
vim.keymap.set("n", "<leader>cr", function()
	run_env_cmd("NVIM_RUN_CMD")
end, { desc = "Run Project" })
vim.keymap.set("n", "<leader>ct", function()
	Snacks.terminal()
end, { desc = "Terminal" })
