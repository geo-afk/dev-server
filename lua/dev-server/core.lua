local M = {}

-- State storage for all servers
M.servers = {}
M.config = {}

-- Debug mode flag
M.debug = false

-- Default configuration
M.default_config = {
	window = {
		type = "split",
		position = "botright",
		size = 15,
	},
	-- Default keymaps (can be disabled with false)
	keymaps = {
		toggle = "<leader>dt",
		restart = "<leader>dr",
		stop = "<leader>ds",
		status = "<leader>dS",
	},
	-- Auto-start servers when entering project
	auto_start = false,
	-- Show notifications
	notifications = {
		enabled = true,
		level = {
			start = vim.log.levels.INFO,
			stop = vim.log.levels.INFO,
			error = vim.log.levels.ERROR,
		},
	},
	-- Server definitions with file type associations
	servers = {},
	-- Enable debug mode
	debug = false,
}

-- ============================================================================
-- Debug Helpers
-- ============================================================================

local function debug_log(...)
	if not M.debug then
		return
	end
	local args = { ... }
	local msg = table.concat(
		vim.tbl_map(function(v)
			if type(v) == "table" then
				return vim.inspect(v)
			end
			return tostring(v)
		end, args),
		" "
	)
	vim.notify("[DevServer Debug] " .. msg, vim.log.levels.DEBUG)
end

-- ============================================================================
-- File Type Detection
-- ============================================================================

M.filetype_mappings = {
	-- JavaScript/TypeScript ecosystems
	javascript = { "npm", "node", "bun", "deno" },
	typescript = { "npm", "node", "bun", "deno" },
	javascriptreact = { "npm", "node", "bun", "deno" },
	typescriptreact = { "npm", "node", "bun", "deno" },
	vue = { "npm", "node" },
	svelte = { "npm", "node" },

	-- Python
	python = { "python", "django", "flask" },

	-- Ruby
	ruby = { "rails", "sinatra" },

	-- Go
	go = { "go" },

	-- Rust
	rust = { "cargo" },

	-- PHP
	php = { "php" },

	-- Java/Kotlin
	java = { "maven", "gradle" },
	kotlin = { "maven", "gradle" },

	-- Other web
	html = { "npm", "node" },
	css = { "npm", "node" },
	scss = { "npm", "node" },
	sass = { "npm", "node" },
}

-- Project marker files for detection
M.project_markers = {
	-- JavaScript/Node
	{ "package.json", { "npm", "node", "bun", "deno" } },
	{ "deno.json", { "deno" } },
	{ "bun.lockb", { "bun" } },

	-- Python
	{ "requirements.txt", { "python" } },
	{ "setup.py", { "python" } },
	{ "pyproject.toml", { "python" } },
	{ "manage.py", { "django" } },
	{ "app.py", { "flask" } },

	-- Ruby
	{ "Gemfile", { "rails", "sinatra" } },
	{ "config.ru", { "rails", "sinatra" } },

	-- Go
	{ "go.mod", { "go" } },

	-- Rust
	{ "Cargo.toml", { "cargo" } },

	-- PHP
	{ "composer.json", { "php" } },

	-- Java/Kotlin
	{ "pom.xml", { "maven" } },
	{ "build.gradle", { "gradle" } },
	{ "build.gradle.kts", { "gradle" } },

	-- Generic
	{ ".git", nil }, -- Any git project
}

---@param bufnr number|nil Buffer number (defaults to current)
---@return string|nil filetype The detected filetype
function M.get_buffer_filetype(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	local ok, ft = pcall(vim.api.nvim_get_option_value, "filetype", { buf = bufnr })
	if not ok or ft == "" then
		debug_log("get_buffer_filetype: no filetype for buffer", bufnr)
		return nil
	end

	debug_log("get_buffer_filetype: buffer", bufnr, "has filetype", ft)
	return ft
end

---@param filetype string
---@return string[]|nil server_types Compatible server types
function M.get_servers_for_filetype(filetype)
	local servers = M.filetype_mappings[filetype]
	debug_log("get_servers_for_filetype:", filetype, "->", servers)
	return servers
end

-- ============================================================================
-- Project Detection
-- ============================================================================

---Find project root by searching upward for marker files
---@param start_path string|nil Starting directory (defaults to current file)
---@return string|nil root_path The project root directory
---@return string|nil marker The marker file that was found
function M.find_project_root(start_path)
	start_path = start_path or vim.fn.expand("%:p:h")

	-- Handle empty buffers or invalid paths
	if start_path == "" or start_path == "." then
		start_path = vim.fn.getcwd()
	end

	debug_log("find_project_root: starting from", start_path)

	local current_dir = start_path
	local home_dir = vim.fn.expand("~")

	-- Search upward for project markers
	while current_dir ~= "/" and current_dir ~= "." and current_dir ~= home_dir do
		for _, marker_data in ipairs(M.project_markers) do
			local marker = marker_data[1]
			local marker_path = current_dir .. "/" .. marker

			if vim.fn.filereadable(marker_path) == 1 or vim.fn.isdirectory(marker_path) == 1 then
				debug_log("find_project_root: found marker", marker, "at", current_dir)
				return current_dir, marker
			end
		end

		-- Move up one directory
		local parent = vim.fn.fnamemodify(current_dir, ":h")
		if parent == current_dir then
			break
		end
		current_dir = parent
	end

	debug_log("find_project_root: no marker found")
	return nil, nil
end

---Check if current buffer is in a project with configured servers
---@param bufnr number|nil Buffer number (defaults to current)
---@return boolean is_in_project
---@return string[]|nil available_servers
function M.is_in_project(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	debug_log("is_in_project: checking buffer", bufnr)

	-- Get buffer path
	local buf_path = vim.api.nvim_buf_get_name(bufnr)
	if buf_path == "" then
		debug_log("is_in_project: buffer has no name")
		return false, nil
	end

	debug_log("is_in_project: buffer path is", buf_path)

	-- Find project root
	local root, marker = M.find_project_root(vim.fn.fnamemodify(buf_path, ":p:h"))
	if not root then
		debug_log("is_in_project: no project root found")
		return false, nil
	end

	debug_log("is_in_project: found root", root, "with marker", marker)

	-- Check if any configured servers match this project
	local available_servers = {}

	debug_log("is_in_project: configured servers:", vim.tbl_keys(M.servers))

	-- First, check marker-based detection
	for _, marker_data in ipairs(M.project_markers) do
		if marker_data[1] == marker and marker_data[2] then
			debug_log("is_in_project: marker", marker, "suggests servers:", marker_data[2])
			for _, server_type in ipairs(marker_data[2]) do
				if M.servers[server_type] then
					debug_log("is_in_project: adding server", server_type, "(from marker)")
					table.insert(available_servers, server_type)
				else
					debug_log("is_in_project: server", server_type, "suggested but not configured")
				end
			end
		end
	end

	-- Also check filetype-based detection
	local ft = M.get_buffer_filetype(bufnr)
	if ft then
		local ft_servers = M.get_servers_for_filetype(ft)
		if ft_servers then
			debug_log("is_in_project: filetype", ft, "suggests servers:", ft_servers)
			for _, server_type in ipairs(ft_servers) do
				if M.servers[server_type] and not vim.tbl_contains(available_servers, server_type) then
					debug_log("is_in_project: adding server", server_type, "(from filetype)")
					table.insert(available_servers, server_type)
				end
			end
		end
	end

	debug_log("is_in_project: final available servers:", available_servers)
	return #available_servers > 0, available_servers
end

-- ============================================================================
-- Private Helper Functions
-- ============================================================================

function M._notify(msg, level)
	if M.config.notifications and M.config.notifications.enabled then
		vim.notify(msg, level)
	end
end

function M._is_job_running(job_id)
	if not job_id or job_id <= 0 then
		return false
	end

	local ok, result = pcall(vim.fn.jobwait, { job_id }, 0)
	if not ok then
		return false
	end

	return result[1] == -1
end

function M._stop_job(job_id)
	if job_id and M._is_job_running(job_id) then
		pcall(vim.fn.jobstop, job_id)
	end
end

function M._create_terminal_buffer()
	local ok, buf_id = pcall(vim.api.nvim_create_buf, false, true)
	if not ok then
		return nil
	end

	pcall(vim.api.nvim_set_option_value, "bufhidden", "hide", { buf = buf_id })
	pcall(vim.api.nvim_set_option_value, "buflisted", false, { buf = buf_id })
	pcall(vim.api.nvim_set_option_value, "swapfile", false, { buf = buf_id })

	pcall(vim.api.nvim_buf_set_keymap, buf_id, "t", "<C-\\><C-n>", "<C-\\><C-n>", {
		noremap = true,
		silent = true,
		desc = "Exit terminal mode",
	})

	return buf_id
end

function M._start_terminal_in_buffer(buf_id, cmd, cwd)
	local ok, job_id = pcall(vim.api.nvim_buf_call, buf_id, function()
		local opts = {
			on_exit = function(j_id, exit_code, _)
				M._handle_job_exit(j_id, exit_code)
			end,
		}
		if cwd then
			opts.cwd = cwd
		end
		return vim.fn.termopen(cmd, opts)
	end)

	if not ok or not job_id or job_id <= 0 then
		return nil
	end

	return job_id
end

function M._handle_job_exit(job_id, exit_code)
	for name, server in pairs(M.servers) do
		if server.job_id == job_id then
			server.exit_code = exit_code
			server.job_id = nil

			local level = M.config.notifications.level.stop
			if exit_code ~= 0 then
				level = M.config.notifications.level.error
			end

			local msg = string.format("Server '%s' exited with code %d", name, exit_code)
			M._notify(msg, level)
			break
		end
	end
end

function M._create_split_window(buf_id, config)
	local size = config.size or 15
	local position = config.position or "botright"
	local split_cmd = config.type == "vsplit" and "vsplit" or "split"

	local ok = pcall(vim.cmd, position .. " " .. size .. split_cmd)
	if not ok then
		return nil
	end

	local win_id = vim.api.nvim_get_current_win()
	pcall(vim.api.nvim_win_set_buf, win_id, buf_id)
	pcall(vim.api.nvim_set_option_value, "number", false, { win = win_id })
	pcall(vim.api.nvim_set_option_value, "relativenumber", false, { win = win_id })
	pcall(vim.api.nvim_set_option_value, "signcolumn", "no", { win = win_id })

	return win_id
end

function M._create_floating_window(buf_id, config)
	local opts = config.float_opts or {}
	local width = opts.width or 0.8
	local height = opts.height or 0.6

	if width > 0 and width < 1 then
		width = math.floor(vim.o.columns * width)
	end
	if height > 0 and height < 1 then
		height = math.floor(vim.o.lines * height)
	end

	local row = opts.row or 0.5
	local col = opts.col or 0.5
	if row > 0 and row < 1 then
		row = math.floor((vim.o.lines - height) * row)
	end
	if col > 0 and col < 1 then
		col = math.floor((vim.o.columns - width) * col)
	end

	local win_opts = {
		relative = opts.relative or "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = opts.border or "rounded",
	}

	local ok, win_id = pcall(vim.api.nvim_open_win, buf_id, true, win_opts)
	if not ok then
		return nil
	end

	pcall(vim.api.nvim_set_option_value, "number", false, { win = win_id })
	pcall(vim.api.nvim_set_option_value, "relativenumber", false, { win = win_id })
	pcall(vim.api.nvim_set_option_value, "signcolumn", "no", { win = win_id })

	return win_id
end

function M._hide_window(win_id)
	if win_id and vim.api.nvim_win_is_valid(win_id) then
		pcall(vim.api.nvim_win_close, win_id, false)
	end
end

-- ============================================================================
-- Public API Functions
-- ============================================================================

function M.toggle(server_name)
	if not M.servers[server_name] then
		M._notify("Server '" .. server_name .. "' not configured", vim.log.levels.ERROR)
		return false
	end

	local server = M.servers[server_name]

	-- Hide if already visible
	if server.win_id and vim.api.nvim_win_is_valid(server.win_id) then
		M._hide_window(server.win_id)
		server.win_id = nil
		server.is_visible = false
		return true
	end

	-- Determine if we need a new buffer
	local needs_new_buffer = false

	if not server.buf_id or not vim.api.nvim_buf_is_valid(server.buf_id) then
		needs_new_buffer = true
	elseif not M._is_job_running(server.job_id) then
		pcall(vim.api.nvim_buf_delete, server.buf_id, { force = true })
		needs_new_buffer = true
	end

	if needs_new_buffer then
		server.buf_id = M._create_terminal_buffer()
		if not server.buf_id then
			M._notify("Failed to create buffer for '" .. server_name .. "'", vim.log.levels.ERROR)
			return false
		end

		-- Resolve cwd
		local cwd = server.config.cwd
		if not cwd or cwd == "" then
			local root = M.find_project_root()
			cwd = root or vim.fn.getcwd()
		end

		server.job_id = M._start_terminal_in_buffer(server.buf_id, server.config.cmd, cwd)
		if not server.job_id or server.job_id <= 0 then
			M._notify("Failed to start server '" .. server_name .. "'", vim.log.levels.ERROR)
			return false
		end

		M._notify("Server '" .. server_name .. "' started", M.config.notifications.level.start)
	end

	-- Create window
	local win_config = server.config.window or M.config.window
	local win_id

	if win_config.type == "float" then
		win_id = M._create_floating_window(server.buf_id, win_config)
	else
		win_id = M._create_split_window(server.buf_id, win_config)
	end

	if not win_id then
		M._notify("Failed to create window for '" .. server_name .. "'", vim.log.levels.ERROR)
		return false
	end

	server.win_id = win_id
	server.is_visible = true
	vim.cmd("startinsert")

	return true
end

function M.restart(server_name)
	local server = M.servers[server_name]
	if not server then
		M._notify("Server '" .. server_name .. "' not configured", vim.log.levels.ERROR)
		return false
	end

	local was_visible = server.is_visible

	-- Hide window
	if server.is_visible then
		M._hide_window(server.win_id)
		server.win_id = nil
		server.is_visible = false
	end

	-- Stop job
	if M._is_job_running(server.job_id) then
		M._stop_job(server.job_id)
		vim.wait(100)
	end

	-- Clean up buffer
	if server.buf_id and vim.api.nvim_buf_is_valid(server.buf_id) then
		pcall(vim.api.nvim_buf_delete, server.buf_id, { force = true })
	end

	server.buf_id = nil
	server.job_id = nil
	server.exit_code = nil

	if was_visible then
		M._notify("Restarting server '" .. server_name .. "'...", vim.log.levels.INFO)
		vim.defer_fn(function()
			M.toggle(server_name)
		end, 200)
	else
		M._notify("Server '" .. server_name .. "' stopped", vim.log.levels.INFO)
	end

	return true
end

function M.stop(server_name)
	local server = M.servers[server_name]
	if not server then
		M._notify("Server '" .. server_name .. "' not configured", vim.log.levels.ERROR)
		return false
	end

	if server.is_visible then
		M._hide_window(server.win_id)
		server.win_id = nil
		server.is_visible = false
	end

	if M._is_job_running(server.job_id) then
		M._stop_job(server.job_id)
		M._notify("Server '" .. server_name .. "' stopped", M.config.notifications.level.stop)
	end

	return true
end

function M.stop_all()
	for name, server in pairs(M.servers) do
		if M._is_job_running(server.job_id) then
			M._stop_job(server.job_id)
		end
	end
	return true
end

function M.get_status(server_name)
	local server = M.servers[server_name]
	if not server then
		return "not configured"
	end

	if M._is_job_running(server.job_id) then
		return server.is_visible and "running (visible)" or "running (hidden)"
	elseif server.exit_code then
		return "exited(" .. server.exit_code .. ")"
	else
		return "stopped"
	end
end

---Get statusline component for current buffer's project
---@param server_name string|nil Specific server name (optional)
---@param bufnr number|nil Buffer number (defaults to current buffer)
---@return string status Empty string if no relevant active server
function M.get_statusline(server_name, bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	debug_log("get_statusline: called for buffer", bufnr, "with server_name", server_name)

	-- If specific server requested, just show that
	if server_name then
		local server = M.servers[server_name]
		debug_log("get_statusline: checking specific server", server_name)
		if server and M._is_job_running(server.job_id) then
			local icon = server.is_visible and "●" or "○"
			local result = string.format(" %s %s", icon, server_name)
			debug_log("get_statusline: returning", result)
			return result
		end
		debug_log("get_statusline: server not running or not found")
		return ""
	end

	-- Check if current buffer is in a project with available servers
	local in_project, available_servers = M.is_in_project(bufnr)
	debug_log("get_statusline: in_project =", in_project, "available_servers =", available_servers)

	if not in_project or not available_servers or #available_servers == 0 then
		debug_log("get_statusline: not in project or no available servers")
		return ""
	end

	-- Show first running server that's relevant to this project
	for _, server_name_iter in ipairs(available_servers) do
		local server = M.servers[server_name_iter]
		debug_log("get_statusline: checking server", server_name_iter, "running =", M._is_job_running(server.job_id))
		if server and M._is_job_running(server.job_id) then
			local icon = server.is_visible and "●" or "○"
			local result = string.format(" %s %s", icon, server_name_iter)
			debug_log("get_statusline: returning", result)
			return result
		end
	end

	debug_log("get_statusline: no running servers found")
	return ""
end

function M.list()
	local servers = {}
	for name, _ in pairs(M.servers) do
		table.insert(servers, {
			name = name,
			status = M.get_status(name),
		})
	end
	table.sort(servers, function(a, b)
		return a.name < b.name
	end)
	return servers
end

function M.register(name, config)
	if not config or type(config) ~= "table" then
		M._notify("Server config must be a table", vim.log.levels.ERROR)
		return false
	end

	if not config.cmd or config.cmd == "" then
		M._notify("Server config must include 'cmd'", vim.log.levels.ERROR)
		return false
	end

	local server_config = vim.tbl_deep_extend("force", {
		window = M.config.window,
	}, config)

	M.servers[name] = {
		config = server_config,
		job_id = nil,
		buf_id = nil,
		win_id = nil,
		is_visible = false,
		exit_code = nil,
	}

	debug_log("register: registered server", name, "with config", server_config)
	return true
end

function M.unregister(name)
	if M.servers[name] then
		M.stop(name)
		M.servers[name] = nil
		return true
	end
	return false
end

-- ============================================================================
-- Keymapping System
-- ============================================================================

---Setup buffer-local keymaps for project buffers
---@param bufnr number Buffer number
function M._setup_buffer_keymaps(bufnr)
	if not M.config.keymaps then
		return
	end

	local in_project, available_servers = M.is_in_project(bufnr)
	if not in_project or not available_servers or #available_servers == 0 then
		return
	end

	-- Get primary server (first in list)
	local primary_server = available_servers[1]

	local function map(mode, lhs, rhs, desc)
		if not lhs or lhs == false then
			return
		end
		vim.api.nvim_buf_set_keymap(bufnr, mode, lhs, "", {
			callback = rhs,
			noremap = true,
			silent = true,
			desc = desc,
		})
	end

	-- Setup keymaps
	map("n", M.config.keymaps.toggle, function()
		M.toggle(primary_server)
	end, "Toggle dev server")

	map("n", M.config.keymaps.restart, function()
		M.restart(primary_server)
	end, "Restart dev server")

	map("n", M.config.keymaps.stop, function()
		M.stop(primary_server)
	end, "Stop dev server")

	map("n", M.config.keymaps.status, function()
		local status = M.get_status(primary_server)
		vim.notify("Server '" .. primary_server .. "': " .. status, vim.log.levels.INFO)
	end, "Show dev server status")
end

-- ============================================================================
-- Setup and Initialization
-- ============================================================================

function M.setup(opts)
	opts = opts or {}

	-- Merge configuration
	M.config = vim.tbl_deep_extend("force", M.default_config, opts)

	-- Set debug mode
	M.debug = M.config.debug or false

	debug_log("setup: initializing with config", M.config)

	-- Register servers
	if M.config.servers then
		for name, config in pairs(M.config.servers) do
			M.register(name, config)
		end
	end

	debug_log("setup: registered servers:", vim.tbl_keys(M.servers))

	-- Create commands
	M._create_commands()

	-- Setup autocommands
	M._setup_autocmds()

	return true
end

function M._create_commands()
	vim.api.nvim_create_user_command("DevServerToggle", function(o)
		if o.args == "" then
			-- Auto-detect server from current buffer
			local in_project, available_servers = M.is_in_project()
			if in_project and available_servers and #available_servers > 0 then
				M.toggle(available_servers[1])
			else
				M._notify("No server configured for current buffer", vim.log.levels.WARN)
			end
		else
			M.toggle(o.args)
		end
	end, {
		nargs = "?",
		complete = function()
			return vim.tbl_keys(M.servers)
		end,
		desc = "Toggle development server visibility",
	})

	vim.api.nvim_create_user_command("DevServerRestart", function(o)
		if o.args == "" then
			local in_project, available_servers = M.is_in_project()
			if in_project and available_servers and #available_servers > 0 then
				M.restart(available_servers[1])
			else
				M._notify("No server configured for current buffer", vim.log.levels.WARN)
			end
		else
			M.restart(o.args)
		end
	end, {
		nargs = "?",
		complete = function()
			return vim.tbl_keys(M.servers)
		end,
		desc = "Restart development server",
	})

	vim.api.nvim_create_user_command("DevServerStop", function(o)
		if o.args == "" then
			local in_project, available_servers = M.is_in_project()
			if in_project and available_servers and #available_servers > 0 then
				M.stop(available_servers[1])
			else
				M._notify("No server configured for current buffer", vim.log.levels.WARN)
			end
		else
			M.stop(o.args)
		end
	end, {
		nargs = "?",
		complete = function()
			return vim.tbl_keys(M.servers)
		end,
		desc = "Stop development server",
	})

	vim.api.nvim_create_user_command("DevServerStatus", function(o)
		if o.args ~= "" then
			local status = M.get_status(o.args)
			vim.notify("Server '" .. o.args .. "': " .. status, vim.log.levels.INFO)
		else
			local servers = M.list()
			if #servers == 0 then
				vim.notify("No servers configured", vim.log.levels.INFO)
			else
				vim.notify("Development Servers:", vim.log.levels.INFO)
				for _, s in ipairs(servers) do
					print(string.format("  %-20s %s", s.name, s.status))
				end
			end
		end
	end, {
		nargs = "?",
		complete = function()
			return vim.tbl_keys(M.servers)
		end,
		desc = "Show server status",
	})

	vim.api.nvim_create_user_command("DevServerList", function()
		local servers = M.list()
		if #servers == 0 then
			vim.notify("No servers configured", vim.log.levels.INFO)
			return
		end

		vim.notify("Available servers:", vim.log.levels.INFO)
		for _, s in ipairs(servers) do
			print(string.format("  %-20s %s", s.name, s.status))
		end
	end, {
		desc = "List all configured servers",
	})

	-- Add debug command
	vim.api.nvim_create_user_command("DevServerDebug", function()
		vim.notify("DevServer Debug Info:", vim.log.levels.INFO)
		print("Debug mode: " .. tostring(M.debug))
		print("Configured servers: " .. vim.inspect(vim.tbl_keys(M.servers)))
		print("\nCurrent buffer info:")
		local bufnr = vim.api.nvim_get_current_buf()
		print("  Buffer: " .. bufnr)
		print("  Path: " .. vim.api.nvim_buf_get_name(bufnr))
		print("  Filetype: " .. (M.get_buffer_filetype(bufnr) or "none"))

		local root, marker = M.find_project_root()
		print("\nProject detection:")
		print("  Root: " .. (root or "not found"))
		print("  Marker: " .. (marker or "none"))

		local in_project, available = M.is_in_project(bufnr)
		print("\nProject status:")
		print("  In project: " .. tostring(in_project))
		print("  Available servers: " .. vim.inspect(available or {}))

		print("\nServer states:")
		for name, server in pairs(M.servers) do
			print(string.format("  %s:", name))
			print(string.format("    Status: %s", M.get_status(name)))
			print(string.format("    Job ID: %s", tostring(server.job_id)))
			print(string.format("    Running: %s", tostring(M._is_job_running(server.job_id))))
		end

		print("\nStatusline output:")
		print("  " .. M.get_statusline())
	end, {
		desc = "Show DevServer debug information",
	})
end

function M._setup_autocmds()
	local group = vim.api.nvim_create_augroup("DevServerCleanup", { clear = true })

	-- Stop all servers on exit
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			M.stop_all()
		end,
		desc = "Stop all dev servers on exit",
	})

	-- Setup buffer-local keymaps when entering buffers
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
		group = group,
		callback = function(args)
			M._setup_buffer_keymaps(args.buf)
		end,
		desc = "Setup dev server keymaps for project buffers",
	})

	-- Auto-start servers if configured
	if M.config.auto_start then
		vim.api.nvim_create_autocmd("BufEnter", {
			group = group,
			callback = function(args)
				local in_project, available_servers = M.is_in_project(args.buf)
				if in_project and available_servers and #available_servers > 0 then
					for _, server_name in ipairs(available_servers) do
						local server = M.servers[server_name]
						if server and not M._is_job_running(server.job_id) then
							-- Auto-start without showing window
							local buf_id = M._create_terminal_buffer()
							if buf_id then
								local root = M.find_project_root()
								local cwd = server.config.cwd or root or vim.fn.getcwd()
								server.job_id = M._start_terminal_in_buffer(buf_id, server.config.cmd, cwd)
								server.buf_id = buf_id
								if server.job_id and server.job_id > 0 then
									M._notify("Auto-started server '" .. server_name .. "'", vim.log.levels.INFO)
								end
							end
						end
					end
				end
			end,
			desc = "Auto-start dev servers in projects",
		})
	end
end

return M
