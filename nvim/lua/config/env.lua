local M = {}

--- Safely parse a JSON environment variable
---@param var string Environment variable name
---@return table
function M.parse_json_env(var)
	local val = vim.env[var]
	if not val or val == "" then
		return {}
	end

	local ok, data = pcall(vim.json.decode, val)
	if not ok then
		vim.notify(string.format("Failed to parse env var %s: %s", var, data), vim.log.levels.WARN)
		return {}
	end

	return data
end

return M
