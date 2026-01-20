local M = {}

local health = vim.health or require("health")

function M.check()
	health.start("dev-server.nvim")

	-- Check Neovim version
	local nvim_version = vim.version()
	if nvim_version.major >= 0 and nvim_version.minor >= 8 then
		health.ok(string.format("Neovim version: %d.%d.%d", nvim_version.major, nvim_version.minor, nvim_version.patch))
	else
		health.error("Neovim 0.8+ required", {
			"Please upgrade Neovim to version 0.8 or higher",
		})
	end

	-- Check if plugin is loaded
	local ok, core = pcall(require, "dev-server.core")
	if ok then
		health.ok("Plugin loaded successfully")

		-- Check configuration
		if core.config and type(core.config) == "table" then
			health.ok("Configuration loaded")

			-- Check servers
			local server_count = vim.tbl_count(core.servers)
			if server_count > 0 then
				health.ok(string.format("%d server(s) configured", server_count))

				-- List servers
				for name, _ in pairs(core.servers) do
					local status = core.get_status(name)
					health.info(string.format("  • %s: %s", name, status))
				end
			else
				health.warn("No servers configured", {
					"Add servers to your configuration:",
					"  require('dev-server').setup({",
					"    servers = {",
					"      npm = { cmd = 'npm run dev' },",
					"    }",
					"  })",
				})
			end
		else
			health.error("Configuration not loaded")
		end
	else
		health.error("Failed to load plugin", {
			"Error: " .. tostring(core),
		})
	end

	-- Check terminal support
	if vim.fn.has("nvim") == 1 then
		health.ok("Terminal emulation available")
	else
		health.error("Terminal emulation not available")
	end

	-- Check job control
	if vim.fn.has("nvim") == 1 then
		health.ok("Job control available")
	else
		health.error("Job control not available")
	end

	-- Check for common project files in current directory
	health.start("Project Detection")
	local cwd = vim.fn.getcwd()
	local found_markers = {}

	if ok and core.project_markers then
		for _, marker_data in ipairs(core.project_markers) do
			local marker = marker_data[1]
			local path = cwd .. "/" .. marker
			if vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1 then
				table.insert(found_markers, marker)
			end
		end
	end

	if #found_markers > 0 then
		health.ok("Found project markers: " .. table.concat(found_markers, ", "))

		-- Try to detect project
		if ok then
			local root, marker = core.find_project_root(cwd)
			if root then
				health.ok(string.format("Project root detected: %s (marker: %s)", root, marker))
			end
		end
	else
		health.info("No project markers found in current directory")
	end

	-- Check keymaps
	health.start("Keymaps")
	if ok and core.config.keymaps then
		health.ok("Keymaps configured:")
		for action, key in pairs(core.config.keymaps) do
			if key and key ~= false then
				health.info(string.format("  • %s: %s", action, key))
			end
		end
	else
		health.warn("No keymaps configured")
	end
end

return M
