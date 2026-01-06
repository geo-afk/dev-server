local M = {}

-- State storage for all servers
M.servers = {}

-- Default configuration
M.default_config = {
	window = {
		type = "split",
		position = "botright",
		size = 15,
	},
}

-- ============================================================================
-- Private Helper Functions
-- ============================================================================

function M._is_job_running(job_id)
	if not job_id then
		return false
	end
	return vim.fn.jobwait({ job_id }, 0)[1] == -1
end

function M._stop_job(job_id)
	if job_id and M._is_job_running(job_id) then
		vim.fn.jobstop(job_id)
	end
end

function M._create_terminal_buffer()
	local buf_id = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf_id })
	vim.api.nvim_set_option_value("buflisted", false, { buf = buf_id })
	vim.api.nvim_set_option_value("swapfile", false, { buf = buf_id })

	vim.api.nvim_buf_set_keymap(buf_id, "t", "<C-\\><C-n>", "<C-\\><C-n>", {
		noremap = true,
		silent = true,
		desc = "Exit terminal mode",
	})
	return buf_id
end

function M._start_terminal_in_buffer(buf_id, cmd, cwd)
	local job_id = vim.api.nvim_buf_call(buf_id, function()
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
	return job_id
end

function M._handle_job_exit(job_id, exit_code)
	for name, server in pairs(M.servers) do
		if server.job_id == job_id then
			server.exit_code = exit_code
			server.job_id = nil
			local level = exit_code == 0 and vim.log.levels.INFO or vim.log.levels.WARN
			local msg = string.format("Server '%s' exited with code %d", name, exit_code)
			vim.notify(msg, level)
			break
		end
	end
end

function M._create_split_window(buf_id, config)
	local size = config.size or 15
	local position = config.position or "botright"
	local split_cmd = config.type == "vsplit" and "vsplit" or "split"
	vim.cmd(position .. " " .. size .. split_cmd)
	local win_id = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win_id, buf_id)
	vim.api.nvim_set_option_value("number", false, { win = win_id })
	vim.api.nvim_set_option_value("relativenumber", false, { win = win_id })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = win_id })
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

	local win_id = vim.api.nvim_open_win(buf_id, true, win_opts)
	vim.api.nvim_set_option_value("number", false, { win = win_id })
	vim.api.nvim_set_option_value("relativenumber", false, { win = win_id })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = win_id })
	return win_id
end

function M._hide_window(win_id)
	if win_id and vim.api.nvim_win_is_valid(win_id) then
		vim.api.nvim_win_close(win_id, false)
	end
end

-- ============================================================================
-- Public API Functions
-- ============================================================================

function M.toggle(server_name)
	if not M.servers[server_name] then
		vim.notify("Server '" .. server_name .. "' not configured", vim.log.levels.ERROR)
		return
	end

	local server = M.servers[server_name]

	if server.win_id and vim.api.nvim_win_is_valid(server.win_id) then
		M._hide_window(server.win_id)
		server.win_id = nil
		server.is_visible = false
		return
	end

	local needs_new_buffer = false

	if not server.buf_id or not vim.api.nvim_buf_is_valid(server.buf_id) then
		needs_new_buffer = true
	elseif not M._is_job_running(server.job_id) then
		vim.api.nvim_buf_delete(server.buf_id, { force = true })
		needs_new_buffer = true
	end

	if needs_new_buffer then
		server.buf_id = M._create_terminal_buffer()
		server.job_id = M._start_terminal_in_buffer(server.buf_id, server.config.cmd, server.config.cwd)
		if not server.job_id or server.job_id <= 0 then
			vim.notify("Failed to start server '" .. server_name .. "'", vim.log.levels.ERROR)
			return
		end
	end

	local win_config = server.config.window or M.default_config.window
	if win_config.type == "float" then
		server.win_id = M._create_floating_window(server.buf_id, win_config)
	else
		server.win_id = M._create_split_window(server.buf_id, win_config)
	end

	server.is_visible = true
	vim.cmd("startinsert")
end

function M.restart(server_name)
	local server = M.servers[server_name]
	if not server then
		vim.notify("Server '" .. server_name .. "' not configured", vim.log.levels.ERROR)
		return
	end

	local was_visible = server.is_visible

	if server.is_visible then
		M._hide_window(server.win_id)
		server.win_id = nil
		server.is_visible = false
	end

	if M._is_job_running(server.job_id) then
		M._stop_job(server.job_id)
		vim.wait(100)
	end

	if server.buf_id and vim.api.nvim_buf_is_valid(server.buf_id) then
		vim.api.nvim_buf_delete(server.buf_id, { force = true })
	end

	server.buf_id = nil
	server.job_id = nil
	server.exit_code = nil

	if was_visible then
		vim.notify("Restarting server '" .. server_name .. "'...", vim.log.levels.INFO)
		vim.defer_fn(function()
			M.toggle(server_name)
		end, 200)
	else
		vim.notify("Server '" .. server_name .. "' stopped", vim.log.levels.INFO)
	end
end

function M.stop(server_name)
	local server = M.servers[server_name]
	if not server then
		vim.notify("Server '" .. server_name .. "' not configured", vim.log.levels.ERROR)
		return
	end

	if server.is_visible then
		M._hide_window(server.win_id)
		server.win_id = nil
		server.is_visible = false
	end

	if M._is_job_running(server.job_id) then
		M._stop_job(server.job_id)
		vim.notify("Server '" .. server_name .. "' stopped", vim.log.levels.INFO)
	end
end

function M.stop_all()
	for name, server in pairs(M.servers) do
		if M._is_job_running(server.job_id) then
			M._stop_job(server.job_id)
		end
	end
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

function M.list()
	local servers = {}
	for name, _ in pairs(M.servers) do
		table.insert(servers, {
			name = name,
			status = M.get_status(name),
		})
	end
	return servers
end

function M.register(name, config)
	if not config.cmd then
		vim.notify("Server config must include 'cmd'", vim.log.levels.ERROR)
		return false
	end

	local server_config = vim.tbl_deep_extend("force", {
		window = M.default_config.window,
	}, config)

	M.servers[name] = {
		config = server_config,
		job_id = nil,
		buf_id = nil,
		win_id = nil,
		is_visible = false,
		exit_code = nil,
	}
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

function M.setup(opts)
	opts = opts or {}

	if opts.default_window then
		M.default_config.window = vim.tbl_extend("force", M.default_config.window, opts.default_window)
	end

	if opts.servers then
		for name, config in pairs(opts.servers) do
			M.register(name, config)
		end
	end

	M._create_commands()
	M._setup_autocmds()
end

function M._create_commands()
	vim.api.nvim_create_user_command("DevServerToggle", function(o)
		M.toggle(o.args)
	end, {
		nargs = 1,
		complete = function()
			return vim.tbl_keys(M.servers)
		end,
		desc = "Toggle development server visibility",
	})

	vim.api.nvim_create_user_command("DevServerRestart", function(o)
		M.restart(o.args)
	end, {
		nargs = 1,
		complete = function()
			return vim.tbl_keys(M.servers)
		end,
		desc = "Restart development server",
	})

	vim.api.nvim_create_user_command("DevServerStop", function(o)
		M.stop(o.args)
	end, {
		nargs = 1,
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
				for _, s in ipairs(servers) do
					print(string.format("%-20s %s", s.name, s.status))
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
end

function M._setup_autocmds()
	local group = vim.api.nvim_create_augroup("DevServerCleanup", { clear = true })
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			M.stop_all()
		end,
		desc = "Stop all dev servers on exit",
	})
end

return M
