local M = {}

local core = require("dev-server.core")

-- Expose all public functions
M.setup = core.setup
M.toggle = core.toggle
M.restart = core.restart
M.stop = core.stop
M.stop_all = core.stop_all
M.get_status = core.get_status
M.list = core.list
M.register = core.register
M.unregister = core.unregister

return M
