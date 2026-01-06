# dev-server.nvim

A lightweight Neovim plugin for managing and toggling development servers (or any long-running terminal processes) directly inside Neovim, with dedicated terminal windows that can be shown/hidden without stopping the process.

Perfect for local development workflows where you want to quickly check server output (e.g., Vite, Django, Rails, Next.js dev servers) without leaving Neovim.

## Features

- **Toggle visibility** of a server terminal with a single command — hide/show without killing the process.
- **Restart** or **stop** individual servers cleanly.
- **Multiple window types**: horizontal split (default), vertical split, or floating window.
- **Automatic cleanup** on Neovim exit.
- User commands with completion and status reporting.
- Minimal dependencies — pure Lua, works on Neovim ≥ 0.8.

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
  -- Optional: override default window settings
  default_window = {
    type = "split",        -- "split" (horizontal), "vsplit" (vertical), or "float"
    position = "botright", -- for splits: "topleft", "botright", etc.
    size = 15,             -- height (split) or width (vsplit)
  },

  -- Define your development servers
  servers = {
    vite = {
      cmd = "npm run dev",           -- required
      cwd = "~/projects/my-vite-app",-- optional: working directory
      window = {                     -- optional: per-server window override
        type = "split",
        position = "botright",
        size = 20,
      },
    },

    django = {
      cmd = "python manage.py runserver",
      cwd = "~/projects/my-django-app",
      window = {
        type = "float",
        float_opts = {
          width = 0.9,
          height = 0.7,
          border = "rounded",
        },
      },
    },

    rails = {
      cmd = "bin/dev",               -- or "rails server"
      cwd = "~/projects/my-rails-app",
      window = {
        type = "vsplit",
        position = "botright",
        size = 80,                   -- width for vsplit
      },
    },
  },
})
```

## Usage

After setup, the following user commands are available:

| Command                    | Description                                           | Example                        |
|----------------------------|-------------------------------------------------------|--------------------------------|
| `:DevServerToggle <name>`  | Show/hide the server terminal                         | `:DevServerToggle vite`        |
| `:DevServerRestart <name>` | Stop and restart the server (keeps visibility state)  | `:DevServerRestart django`     |
| `:DevServerStop <name>`    | Stop the server and hide window                       | `:DevServerStop rails`         |
| `:DevServerStatus [name]`  | Show status of one server or all servers              | `:DevServerStatus` or `:DevServerStatus vite` |

All commands support tab-completion of registered server names.

### Keybinding suggestions

```lua
vim.keymap.set("n", "<leader>dv", ":DevServerToggle vite<CR>", { desc = "Toggle Vite server" })
vim.keymap.set("n", "<leader>dd", ":DevServerToggle django<CR>", { desc = "Toggle Django server" })
vim.keymap.set("n", "<leader>dr", ":DevServerToggle rails<CR>", { desc = "Toggle Rails server" })
```

### Terminal interaction

When a server terminal is visible:
- You are automatically placed in **insert (terminal) mode**.
- Press `<C-\><C-n>` to exit terminal mode (as in any Neovim terminal).
- The terminal buffer has `<C-\><C-n>` mapped in terminal mode for convenience.

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

## Status Reporting

Running `:DevServerStatus` without arguments prints a table of all configured servers:

```
vite                 running (visible)
django               running (hidden)
rails                exited(1)
```

## Cleanup

All running servers are automatically stopped when Neovim exits (`VimLeavePre`).

## Contributing

Feel free to open issues or PRs! This plugin is intentionally kept small and focused.

## License

MIT License
