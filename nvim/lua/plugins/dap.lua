local dap = require("dap")
local dapui = require("dapui")
local utils = require("config.env")

dap.adapters.debugpy = {
	type = "executable",
	command = "python",
	args = { "-m", "debugpy.adapter" },
}

dap.adapters.codelldb = {
	type = "server",
	port = "${port}",
	executable = {
		command = "codelldb",
		args = { "--port", "${port}" },
	},
}

dapui.setup()

-- Auto-open/close DAP UI
dap.listeners.after.event_initialized["dapui_config"] = function()
	dapui.open()
end
dap.listeners.before.event_terminated["dapui_config"] = function()
	dapui.close()
end
dap.listeners.before.event_exited["dapui_config"] = function()
	dapui.close()
end

local env_dap = utils.parse_json_env("NVIM_DAP_CONFIGS")
for ft, configs in pairs(env_dap) do
	dap.configurations[ft] = dap.configurations[ft] or {}
	vim.list_extend(dap.configurations[ft], configs)
end

vim.keymap.set("n", "<leader>db", dap.toggle_breakpoint, { desc = "Debug Breakpoint" })
vim.keymap.set("n", "<leader>dc", dap.continue, { desc = "Debug Continue/Start" })
vim.keymap.set("n", "<leader>di", dap.step_into, { desc = "Debug Step Into" })
vim.keymap.set("n", "<leader>do", dap.step_over, { desc = "Debug Step Over" })
vim.keymap.set("n", "<leader>du", dapui.toggle, { desc = "Debug Toggle UI" })
