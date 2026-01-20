local M = {}

local core = require("dev-server.core")

-- ============================================================================
-- Core Functions
-- ============================================================================

M.setup = core.setup
M.toggle = core.toggle
M.restart = core.restart
M.stop = core.stop
M.stop_all = core.stop_all
M.get_status = core.get_status
M.list = core.list
M.register = core.register
M.unregister = core.unregister

-- ============================================================================
-- Statusline Integration
-- ============================================================================

---Get statusline component
---@param server_name string|nil Optional server name (ignores project context if provided)
---@param bufnr number|nil Buffer number (defaults to current buffer)
---@return string statusline Empty string if no relevant active server
M.get_statusline = core.get_statusline

-- ============================================================================
-- Project Detection
-- ============================================================================

---Find project root directory
---@param start_path string|nil Starting path
---@return string|nil root Project root directory
---@return string|nil marker Marker file that was found
M.find_project_root = core.find_project_root

---Check if buffer is in a project
---@param bufnr number|nil Buffer number
---@return boolean in_project
---@return string[]|nil available_servers
M.is_in_project = core.is_in_project

-- ============================================================================
-- File Type Detection
-- ============================================================================

---Get buffer's file type
---@param bufnr number|nil Buffer number
---@return string|nil filetype
M.get_buffer_filetype = core.get_buffer_filetype

---Get compatible servers for a file type
---@param filetype string
---@return string[]|nil server_types
M.get_servers_for_filetype = core.get_servers_for_filetype

return M
