-- core.lua
local M = {}

-- State storage for all servers
M.servers = {}
M.config = {}

-- Default configuration
M.default_config = {
	window = {
		type = "split",
		position = "botright",
		size = 15,
	},
	keymaps = {
		toggle = "<leader>dt",
		restart = "<leader>dr",
		stop = "<leader>ds",
		status = "<leader>dS",
	},
	auto_start = false,
	notifications = {
		enabled = true,
		level = {
			start = vim.log.levels.INFO,
			stop = vim.log.levels.INFO,
			error = vim.log.levels.ERROR,
		},
	},
	servers = {},
}

-- ============================================================================
-- File Type Detection (kept as fallback / helper)
-- ============================================================================

M.filetype_mappings = {
	-- (you can keep or remove — now less important)
	javascript = { "npm", "node", "bun", "deno" },
	typescript = { "npm", "node", "bun", "deno" },
	javascriptreact = { "npm", "node", "bun", "deno" },
	typescriptreact = { "npm", "node", "bun", "deno" },
	vue = { "npm", "node" },
	svelte = { "npm", "node" },
	python = { "python", "django", "flask" },
	ruby = { "rails", "sinatra" },
	go = { "go" },
	rust = { "cargo" },
	php = { "php" },
	java = { "maven", "gradle" },
	kotlin = { "maven", "gradle" },
	html = { "npm", "node" },
	css = { "npm", "node" },
	scss = { "npm", "node" },
	sass = { "npm", "node" },
}

-- Project marker files (used only as legacy fallback — new detect system preferred)
M.project_markers = {
	{ "package.json", { "npm", "node", "bun", "deno" } },
	{ "deno.json", { "deno" } },
	{ "bun.lockb", { "bun" } },
	{ "requirements.txt", { "python" } },
	{ "pyproject.toml", { "python" } },
	{ "manage.py", { "django" } },
	{ "app.py", { "flask" } },
	{ "Gemfile", { "rails", "sinatra" } },
	{ "go.mod", { "go" } },
	{ "Cargo.toml", { "cargo" } },
	{ "composer.json", { "php" } },
	{ "pom.xml", { "maven" } },
	{ "build.gradle", { "gradle" } },
	{ ".git", nil },
}

---@param bufnr number|nil
---@return string|nil
function M.get_buffer_filetype(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local ok, ft = pcall(vim.api.nvim_get_option_value, "filetype", { buf = bufnr })
	if not ok or ft == "" then
		return nil
	end
	return ft
end

-- ============================================================================
-- Project & Server Detection (main improvement)
-- ============================================================================

---@param start_path string|nil
---@return string|nil root_path
---@return string|nil marker
function M.find_project_root(start_path)
	start_path = start_path or vim.fn.expand("%:p:h")
	if start_path == "" or start_path == "." then
		start_path = vim.fn.getcwd()
	end

	local current = start_path
	local home = vim.fn.expand("~")

	while current ~= "/" and current ~= "." and current ~= home do
		for _, marker_data in ipairs(M.project_markers) do
			local marker = marker_data[1]
			local path = current .. "/" .. marker
			if vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1 then
				return current, marker
			end
		end
		local parent = vim.fn.fnamemodify(current, ":h")
		if parent == current then
			break
		end
		current = parent
	end

	return nil, nil
end

--- Returns whether we're in a project that has at least one matching server
--- and the list of matching server names (ordered by how they were found)
---@param bufnr number|nil
---@return boolean in_project
---@return string[]|nil matched_server_names
function M.is_in_project(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	if bufname == "" then
		return false, nil
	end

	local root = M.find_project_root(vim.fn.fnamemodify(bufname, ":p:h"))
	if not root then
		return false, nil
	end

	local matched = {}
	local seen = {} -- avoid duplicates

	for name, server in pairs(M.servers) do
		local detect = server.config.detect or {}

		-- 1. Strongest: marker file(s)
		local markers = {}
		if detect.marker then
			table.insert(markers, detect.marker)
		end
		if detect.markers then
			vim.list_extend(markers, detect.markers)
		end

		for _, m in ipairs(markers) do
			if vim.fn.filereadable(root .. "/" .. m) == 1 then
				if not seen[name] then
					table.insert(matched, name)
					seen[name] = true
				end
				goto next_server
			end
		end

		-- 2. Fallback: filetypes (only if no marker matched)
		local ft = M.get_buffer_filetype(bufnr)
		local ft_list = detect.filetypes or {}
		if ft and #ft_list > 0 and vim.tbl_contains(ft_list, ft) then
			if not seen[name] then
				table.insert(matched, name)
				seen[name] = true
			end
		end

		::next_server::
	end

	-- Could sort matched by some priority field later if desired
	return #matched > 0, matched
end

-- ============================================================================
-- Private helpers (mostly unchanged)
-- ============================================================================

function M._notify(msg, level)
	if M.config.notifications.enabled then
		vim.notify(msg, level or vim.log.levels.INFO)
	end
end

function M._is_job_running(job_id)
	if not job_id or job_id <= 0 then
		return false
	end
	local ok, res = pcall(vim.fn.jobwait, { job_id }, 0)
	return ok and res[1] == -1
end

function M._stop_job(job_id)
	if job_id and M._is_job_running(job_id) then
		pcall(vim.fn.jobstop, job_id)
	end
end

function M._create_terminal_buffer()
	local ok, buf = pcall(vim.api.nvim_create_buf, false, true)
	if not ok then
		return nil
	end

	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].buflisted = false
	vim.bo[buf].swapfile = false

	vim.keymap.set("t", "<C-\\><C-n>", "<C-\\><C-n>", {
		buffer = buf,
		noremap = true,
		silent = true,
		desc = "Exit terminal mode",
	})

	return buf
end

function M._start_terminal_in_buffer(buf, cmd, cwd)
	local ok, job_id = pcall(vim.api.nvim_buf_call, buf, function()
		local opts = {
			on_exit = function(j, code)
				M._handle_job_exit(j, code)
			end,
		}
		if cwd and cwd ~= "" then
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
	for name, srv in pairs(M.servers) do
		if srv.job_id == job_id then
			srv.job_id = nil
			srv.exit_code = exit_code
			local lvl = (exit_code == 0) and M.config.notifications.level.stop or M.config.notifications.level.error
			M._notify(("Server '%s' exited with code %d"):format(name, exit_code), lvl)
			break
		end
	end
end

function M._create_split_window(buf, cfg)
	local pos = cfg.position or "botright"
	local sz = cfg.size or 15
	local cmd = (cfg.type == "vsplit") and "vsplit" or "split"

	local ok = pcall(vim.cmd, pos .. " " .. sz .. cmd)
	if not ok then
		return nil
	end

	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"

	return win
end

function M._create_floating_window(buf, cfg)
	local o = cfg.float_opts or {}
	local w = math.floor(vim.o.columns * (o.width or 0.8))
	local h = math.floor(vim.o.lines * (o.height or 0.6))
	local r = math.floor((vim.o.lines - h) * (o.row or 0.5))
	local c = math.floor((vim.o.columns - w) * (o.col or 0.5))

	local win_opts = {
		relative = o.relative or "editor",
		width = w,
		height = h,
		row = r,
		col = c,
		style = "minimal",
		border = o.border or "rounded",
	}

	local ok, win = pcall(vim.api.nvim_open_win, buf, true, win_opts)
	if not ok then
		return nil
	end

	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"

	return win
end

function M._hide_window(win)
	if win and vim.api.nvim_win_is_valid(win) then
		pcall(vim.api.nvim_win_close, win, false)
	end
end

-- ============================================================================
-- Public API
-- ============================================================================

function M.toggle(server_name)
	if not M.servers[server_name] then
		M._notify("Server '" .. server_name .. "' not found", vim.log.levels.ERROR)
		return false
	end

	local srv = M.servers[server_name]

	-- already visible → hide
	if srv.win_id and vim.api.nvim_win_is_valid(srv.win_id) then
		M._hide_window(srv.win_id)
		srv.win_id = nil
		srv.is_visible = false
		return true
	end

	-- need new buffer/job?
	local need_restart = not srv.buf_id
		or not vim.api.nvim_buf_is_valid(srv.buf_id)
		or not M._is_job_running(srv.job_id)

	if need_restart then
		if srv.buf_id and vim.api.nvim_buf_is_valid(srv.buf_id) then
			pcall(vim.api.nvim_buf_delete, srv.buf_id, { force = true })
		end

		srv.buf_id = M._create_terminal_buffer()
		if not srv.buf_id then
			return false
		end

		local cwd = srv.config.cwd
		if not cwd or cwd == "" then
			cwd = M.find_project_root() or vim.fn.getcwd()
		end

		srv.job_id = M._start_terminal_in_buffer(srv.buf_id, srv.config.cmd, cwd)
		if not srv.job_id or srv.job_id <= 0 then
			M._notify("Failed to start '" .. server_name .. "'", vim.log.levels.ERROR)
			return false
		end

		M._notify("Started '" .. server_name .. "'", M.config.notifications.level.start)
	end

	-- create window
	local win_cfg = srv.config.window or M.config.window
	local win_id

	if win_cfg.type == "float" then
		win_id = M._create_floating_window(srv.buf_id, win_cfg)
	else
		win_id = M._create_split_window(srv.buf_id, win_cfg)
	end

	if not win_id then
		return false
	end

	srv.win_id = win_id
	srv.is_visible = true
	vim.cmd("startinsert")

	return true
end

function M.restart(server_name)
	local srv = M.servers[server_name]
	if not srv then
		return false
	end

	local was_visible = srv.is_visible

	if srv.is_visible then
		M._hide_window(srv.win_id)
		srv.win_id = nil
		srv.is_visible = false
	end

	if M._is_job_running(srv.job_id) then
		M._stop_job(srv.job_id)
		vim.wait(150)
	end

	if srv.buf_id and vim.api.nvim_buf_is_valid(srv.buf_id) then
		pcall(vim.api.nvim_buf_delete, srv.buf_id, { force = true })
	end

	srv.buf_id = nil
	srv.job_id = nil
	srv.exit_code = nil

	if was_visible then
		vim.defer_fn(function()
			M.toggle(server_name)
		end, 200)
	end

	return true
end

function M.stop(server_name)
	local srv = M.servers[server_name]
	if not srv then
		return false
	end

	if srv.is_visible then
		M._hide_window(srv.win_id)
		srv.win_id = nil
		srv.is_visible = false
	end

	if M._is_job_running(srv.job_id) then
		M._stop_job(srv.job_id)
		M._notify("Stopped '" .. server_name .. "'", M.config.notifications.level.stop)
	end

	return true
end

function M.stop_all()
	for _, srv in pairs(M.servers) do
		if M._is_job_running(srv.job_id) then
			M._stop_job(srv.job_id)
		end
	end
end

function M.get_status(server_name)
	local srv = M.servers[server_name]
	if not srv then
		return "not configured"
	end

	if M._is_job_running(srv.job_id) then
		return srv.is_visible and "running (visible)" or "running (hidden)"
	elseif srv.exit_code then
		return "exited(" .. srv.exit_code .. ")"
	else
		return "stopped"
	end
end

function M.get_statusline(server_name, bufnr)
	if server_name then
		local srv = M.servers[server_name]
		if srv and M._is_job_running(srv.job_id) then
			local icon = srv.is_visible and "●" or "○"
			return " " .. icon .. " " .. server_name
		end
		return ""
	end

	local _, servers = M.is_in_project(bufnr)
	if not servers or #servers == 0 then
		return ""
	end

	for _, name in ipairs(servers) do
		local srv = M.servers[name]
		if srv and M._is_job_running(srv.job_id) then
			local icon = srv.is_visible and "●" or "○"
			return " " .. icon .. " " .. name
		end
	end

	return ""
end

function M.register(name, config)
	if type(config) ~= "table" or not config.cmd or config.cmd == "" then
		M._notify("Invalid server config (cmd required)", vim.log.levels.ERROR)
		return false
	end

	local defaults = {
		window = M.config.window,
		detect = {}, -- ← important new field
	}

	M.servers[name] = {
		config = vim.tbl_deep_extend("force", defaults, config),
		job_id = nil,
		buf_id = nil,
		win_id = nil,
		is_visible = false,
		exit_code = nil,
	}

	return true
end

-- ============================================================================
-- Buffer-local keymaps (uses first matched server)
-- ============================================================================

function M._setup_buffer_keymaps(bufnr)
	if not M.config.keymaps then
		return
	end

	local _, servers = M.is_in_project(bufnr)
	if not servers or #servers == 0 then
		return
	end

	-- For now we take the first match (you can later add a picker)
	local primary = servers[1]

	local function map(lhs, callback, desc)
		if not lhs or lhs == false then
			return
		end
		vim.keymap.set("n", lhs, callback, {
			buffer = bufnr,
			noremap = true,
			silent = true,
			desc = desc,
		})
	end

	map(M.config.keymaps.toggle, function()
		M.toggle(primary)
	end, "Toggle dev server")
	map(M.config.keymaps.restart, function()
		M.restart(primary)
	end, "Restart dev server")
	map(M.config.keymaps.stop, function()
		M.stop(primary)
	end, "Stop dev server")
	map(M.config.keymaps.status, function()
		vim.notify(("Server '%s': %s"):format(primary, M.get_status(primary)))
	end, "Dev server status")
end

-- ============================================================================
-- Setup
-- ============================================================================

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.default_config, opts or {})

	if M.config.servers then
		for name, cfg in pairs(M.config.servers) do
			M.register(name, cfg)
		end
	end

	M._create_commands()
	M._setup_autocmds()

	return true
end

-- (the rest — commands & autocmds — remains mostly the same, just showing the important change)

function M._setup_autocmds()
	local group = vim.api.nvim_create_augroup("DevServer", { clear = true })

	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = M.stop_all,
	})

	vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
		group = group,
		callback = function(ev)
			M._setup_buffer_keymaps(ev.buf)
		end,
	})

	if M.config.auto_start then
		vim.api.nvim_create_autocmd("BufEnter", {
			group = group,
			callback = function(ev)
				local ok, servers = M.is_in_project(ev.buf)
				if not ok or not servers then
					return
				end

				for _, name in ipairs(servers) do
					local srv = M.servers[name]
					if srv and not M._is_job_running(srv.job_id) then
						local buf = M._create_terminal_buffer()
						if not buf then
							goto continue
						end

						local root = M.find_project_root()
						local cwd = srv.config.cwd or root or vim.fn.getcwd()

						srv.job_id = M._start_terminal_in_buffer(buf, srv.config.cmd, cwd)
						srv.buf_id = buf

						if srv.job_id and srv.job_id > 0 then
							M._notify("Auto-started " .. name, vim.log.levels.INFO)
						end
					end
					::continue::
				end
			end,
		})
	end
end

return M
