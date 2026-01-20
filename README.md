# dev-server.nvim

A lightweight Neovim plugin for managing and toggling development servers (or any long-running terminal processes) directly inside Neovim, with dedicated terminal windows that can be shown/hidden without stopping the process.

Perfect for local development workflows where you want to quickly check server output (e.g., Vite, Django, Rails, Next.js dev servers) without leaving Neovim.


## Features

- 🚀 **Project Detection**: Automatically detects project types via marker files (package.json, Cargo.toml, etc.)
- 📝 **File Type Awareness**: Associates file types with appropriate server types
- ⌨️ **Smart Keymaps**: Buffer-local keymaps only appear in relevant project files
- 🪟 **Flexible Windows**: Support for splits, vsplits, and floating windows
- 📊 **Statusline Integration**: Lightweight statusline component (blank when no servers active)
- 🔄 **Auto-start**: Optional auto-start servers when entering projects
- 🎯 **Multiple Servers**: Manage multiple development servers simultaneously
- ⚡ **Terminal Integration**: Full terminal emulation with job control

## Installation

### Using lazy.nvim (recommended)

```lua
{
  "github.com/geo-afk/dev-server.nvim", 
  config = function()
    require("dev-server").setup({
      -- your configuration here
    })
  end,
}
```

### Using packer.nvim

```lua
use {

  "github.com/geo-afk/dev-server.nvim",
  config = function()
    require("dev-server").setup({...})
  end,
}
```

### Using vim-plug

```vim

Plug "github.com/geo-afk/dev-server.nvim"

lua << EOF
require('dev-server').setup({...})
EOF
```

## Setup & Configuration

Call the `setup` function in your configuration. You can define default window behavior and register your servers.

```lua
require("dev-server").setup({
  -- Default window configuration for all servers
  window = {
    type = "split",        -- "split", "vsplit", or "float"
    position = "botright", -- "botright", "topleft", etc.
    size = 15,             -- Height for splits, width for vsplits
  },
  
  -- Keymaps (set to false to disable)
  keymaps = {
    toggle = "<leader>dt",  -- Toggle server visibility
    restart = "<leader>dr", -- Restart server
    stop = "<leader>ds",    -- Stop server
    status = "<leader>dS",  -- Show server status
  },
  
  -- Auto-start servers when entering project
  auto_start = false,
  
  -- Notification settings
  notifications = {
    enabled = true,
    level = {
      start = vim.log.levels.INFO,
      stop = vim.log.levels.INFO,
      error = vim.log.levels.ERROR,
    },
  },
  
  -- Server definitions
  servers = {
    npm = {
      cmd = "npm run dev",
      cwd = nil,  -- Use project root by default
    },
    
    vite = {
      cmd = "npm run dev",
      window = {
        type = "float",
        float_opts = {
          width = 0.9,
          height = 0.9,
          border = "rounded",
        },
      },
    },
    
    cargo = {
      cmd = "cargo run",
    },
    
    go = {
      cmd = "go run .",
    },
    
    django = {
      cmd = "python manage.py runserver",
    },
    
    rails = {
      cmd = "rails server",
    },
  },
})```

## Usage

After setup, the following user commands are available:

| Command                    | Description                                                   | Example                                       |
|----------------------------|---------------------------------------------------------------|-----------------------------------------------|
| `:DevServerToggle [name]`  | Toggle server visibility (auto-detects if no name provided)   | `:DevServerToggle vite`                       |
| `:DevServerRestart [name]` | Stop and restart the server (keeps visibility state)          | `:DevServerRestart django`                    |
| `:DevServerStop [name]`    | Stop the server and hide window                               | `:DevServerStop rails`                        |
| `:DevServerStatus [name]`  | Show server status (lists all if no name provided)            | `:DevServerStatus` or `:DevServerStatus vite` |
| `DevServerList`            | List all Configured Servers                                   | `:DevServerList`                              |



All commands support tab-completion of registered server names.

### Default Keymaps

When in a project buffer with a configured server:

- `<leader>dt` - Toggle server
- `<leader>dr` - Restart server
- `<leader>ds` - Stop server
- `<leader>dS` - Show status

### Lua API

```lua
local dev_server = require("dev-server")

-- Toggle a specific server
dev_server.toggle("npm")

-- Restart server
dev_server.restart("npm")

-- Stop server
dev_server.stop("npm")

-- Stop all servers
dev_server.stop_all()

-- Get server status
local status = dev_server.get_status("npm")
-- Returns: "running (visible)", "running (hidden)", "stopped", "exited(code)", or "not configured"

-- Get statusline component
local statusline = dev_server.get_statusline()
-- Returns: " ● npm" (active) or "" (no active servers)

-- Check if buffer is in a project
local in_project, available_servers = dev_server.is_in_project()
if in_project then
  print("Available servers:", vim.inspect(available_servers))
end

-- Find project root
local root, marker = dev_server.find_project_root()
if root then
  print("Project root:", root, "Marker:", marker)
end

## Window Types

### Split (default)
Horizontal split at the bottom/right:
```lua
window = { type = "split", position = "botright", size = 15 }
```

### Vertical split
```lua
window = { type = "vsplit", position = "botright", size = 80 }
```

### Floating window
```lua
window = {
  type = "float",
  float_opts = {
    width = 0.9,      -- fraction of editor width or absolute pixels
    height = 0.8,
    row = 0.1,        -- top offset fraction
    col = 0.5,        -- centered horizontally
    border = "rounded",
  },
}
```



-- Register a new server
dev_server.register("custom", {
  cmd = "my-dev-command",
  cwd = "/path/to/project",
})

-- List all servers
local servers = dev_server.list()
for _, server in ipairs(servers) do
  print(server.name, server.status)
end
```

## Statusline Integration

### lualine.nvim

```lua
require('lualine').setup({
  sections = {
    lualine_x = {
      function()
        return require('dev-server').get_statusline()
      end,
    },
  },
})
```

### Custom Statusline

```lua
function _G.dev_server_status()
  return require('dev-server').get_statusline()
end

vim.o.statusline = '%f %{v:lua.dev_server_status()}'
```

## Project Detection

The plugin automatically detects projects by searching for marker files:

### Supported Project Types

| Language/Framework | Marker Files | Default Server Types |
|-------------------|--------------|---------------------|
| JavaScript/Node.js | package.json | npm, node, bun, deno |
| TypeScript | package.json, deno.json | npm, node, bun, deno |
| Python | requirements.txt, setup.py, pyproject.toml | python |
| Django | manage.py | django |
| Flask | app.py | flask |
| Ruby/Rails | Gemfile, config.ru | rails, sinatra |
| Go | go.mod | go |
| Rust | Cargo.toml | cargo |
| PHP | composer.json | php |
| Java/Kotlin | pom.xml, build.gradle | maven, gradle |

### File Type Associations

The plugin maps file types to compatible server types:

```lua
-- Example: Opening a .ts file in a project with package.json
-- will make npm/node/bun/deno servers available
```

## Advanced Configuration

### Per-Server Window Configuration

```lua
servers = {
  npm = {
    cmd = "npm run dev",
    window = {
      type = "split",
      position = "botright",
      size = 20,
    },
  },
  
  logs = {
    cmd = "tail -f logs/development.log",
    window = {
      type = "float",
      float_opts = {
        width = 0.8,
        height = 0.6,
        row = 0.5,
        col = 0.5,
        border = "double",
      },
    },
  },
}
```

### Custom Keymaps

```lua
keymaps = {
  toggle = "<C-t>",
  restart = "<C-r>",
  stop = "<C-s>",
  status = false,  -- Disable status keymap
}
```

### Disable All Keymaps

```lua
keymaps = false
```

## Health Check

Run `:checkhealth dev-server` to verify:

- Neovim version compatibility
- Plugin configuration
- Registered servers
- Project detection
- Keymap configuration

## Tips & Tricks

### Auto-start Servers

Enable `auto_start = true` to automatically start servers when entering project files:

```lua
require("dev-server").setup({
  auto_start = true,
  servers = {
    npm = { cmd = "npm run dev" },
  },
})
```

### Multiple Servers in Same Project

Configure multiple servers for different purposes:

```lua
servers = {
  frontend = { cmd = "npm run dev" },
  backend = { cmd = "npm run server" },
  db = { cmd = "docker-compose up db" },
}
```

Then toggle them individually:
```vim
:DevServerToggle frontend
:DevServerToggle backend
```

### Terminal Mode Navigation

Inside the terminal buffer, press `<C-\><C-n>` to enter normal mode for navigation.

## Troubleshooting

### Keymaps not appearing

1. Ensure you're in a buffer that belongs to a detected project
2. Check that servers are configured for your project type
3. Run `:checkhealth dev-server` to verify configuration

### Server not starting

1. Check the command is correct: `:DevServerToggle servername`
2. Verify the command works in a regular terminal
3. Check notifications for error messages
4. Ensure project root is detected correctly

### Project not detected

1. Make sure marker files exist (package.json, Cargo.toml, etc.)
2. Try `:lua print(vim.inspect(require('dev-server').find_project_root()))`
3. Check current working directory with `:pwd`

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

MIT License - see LICENSE file for details
