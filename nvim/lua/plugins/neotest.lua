local neotest = require("neotest")
local utils = require("config.env")

-- 1. Registry of all known adapters (lazy loaded, only initialized if requested)
local available_adapters = {
	["neotest-python"] = require("neotest-python")({
		runner = "pytest",
	}),
	-- Add more as you install them via Nix:
	-- ["neotest-jest"] = require("neotest-jest")({}),
	-- ["neotest-go"] = require("neotest-go")({}),
}

-- 2. Parse env var and load only the project-specific adapters
local active_adapter_names = utils.parse_json_env("NVIM_TEST_ADAPTERS") or {}
local adapters_to_load = {}

for _, name in ipairs(active_adapter_names) do
	if available_adapters[name] then
		table.insert(adapters_to_load, available_adapters[name])
	else
		vim.notify("Unknown neotest adapter: " .. name, vim.log.levels.WARN)
	end
end

-- 3. Setup Neotest
neotest.setup({
	adapters = adapters_to_load,
})

-- 4. Keymaps
vim.keymap.set("n", "<leader>tt", function()
	neotest.run.run(vim.fn.expand("%"))
end, { desc = "Test File" })
vim.keymap.set("n", "<leader>tn", function()
	neotest.run.run()
end, { desc = "Test Nearest" })
vim.keymap.set("n", "<leader>td", function()
	neotest.run.run({ strategy = "dap" })
end, { desc = "Debug Nearest Test" })
vim.keymap.set("n", "<leader>ts", function()
	neotest.summary.toggle()
end, { desc = "Test Summary" })
vim.keymap.set("n", "<leader>to", function()
	neotest.output.open({ enter = true })
end, { desc = "Test Output" })
vim.keymap.set("n", "<leader>tO", function()
	neotest.output_panel.toggle()
end, { desc = "Test Output Panel" })
vim.keymap.set("n", "<leader>tS", function()
	neotest.run.stop()
end, { desc = "Test Stop" })
