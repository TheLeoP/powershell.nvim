# Powershell.nvim

![GitHub Workflow Status](https://github.com/TheLeoP/powershell.nvim/actions/workflows/lint-test.yml/badge.svg)
![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)

This extension provides rich PowerShell language support for Neovim. Now you can write and debug PowerShell scripts using the excellent IDE-like interface that Neovim provides.

## Features

- Powershell LSP support (via [Powershell Editor Services](https://github.com/PowerShell/PowerShellEditorServices))
- [Powershell Extension Terminal](https://github.com/PowerShell/PowerShellEditorServices#powershell-extension-terminal) support
- Debugging support (requires [nvim-dap](https://github.com/mfussenegger/nvim-dap))
- [$psEditor API](https://github.com/PowerShell/PowerShellEditorServices/blob/main/docs/guide/extensions.md) support

## Requirements

- [Powershell Editor Services](https://github.com/PowerShell/PowerShellEditorServices) (can be installed manually or using something like [mason.nvim](https://github.com/williamboman/mason.nvim))
- [Neovim >= 0.10](https://github.com/neovim/neovim/releases/tag/v0.10.0)
- (Optional) [nvim-dap](https://github.com/mfussenegger/nvim-dap) (needed for debugging)

## Installation

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
    "TheLeoP/powershell.nvim"
}
```

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "TheLeoP/powershell.nvim",
    ---@type powershell.user_config
    opts = {
      bundle_path = 'path/to/your/bundle_path/'
    }
}
```

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'TheLeoP/powershell.nvim'
```

## Configuration

The only required field for the plugin to work is `bundle_path`, this has to be the path of where Powershell Editor Services is installed.

For example, if you are using mason with default settings, you would have to do something like the following:

```lua
require('powershell').setup({
  bundle_path = vim.fn.stdpath "data" .. "/mason/packages/powershell-editor-services",
})
```

### Default configuration

```lua
-- This is the default configuration
require('powershell').setup({
  capabilities = vim.lsp.protocol.make_client_capabilities(),
  bundle_path = "",
  init_options = vim.empty_dict(),
  settings = vim.empty_dict(),
  shell = "pwsh",
  handlers = base_handlers, -- see lua/powershell/handlers.lua
  root_dir = function(buf)
    return fs.dirname(fs.find({ ".git" }, { upward = true, path = fs.dirname(api.nvim_buf_get_name(buf)) })[1])
  end,
})
```

## Lua API

### Toggle Powershell Extension Terminal

```lua
require('powershell').toggle_term()
```

To create a keymap only for powershell files, put the following in your config.

```lua
-- this should go in ~/.config/nvim/ftplugin/ps1.lua
vim.keymap.set("n", "<leader>P", function() require("powershell").toggle_term() end)
```

You could also use a filetype autocmd to create the keymap.

### Eval expression on Powershell Extension Terminal

Can be used both in normal (evaluates current line) and visual mode (evaluates visual selection).

```lua
require('powershell').eval()
```

To create a keymap only for powershell files, put the following in your config.

```lua
-- this should go in ~/.config/nvim/ftplugin/ps1.lua
vim.keymap.set("n", "<leader>E", function() require("powershell").eval() end)
vim.keymap.set("v", "<leader>E", function() require("powershell").eval() end)
```

You could also use a filetype autocmd to create the keymap.

## DAP

By default, the plugin includes the following [nvim-dap](https://github.com/mfussenegger/nvim-dap) configurations:

```lua
dap.configurations.ps1 = {
  {
    name = "PowerShell: Launch Current File",
    type = "ps1",
    request = "launch",
    script = "${file}",
  },
  {
    name = "PowerShell: Launch Script",
    type = "ps1",
    request = "launch",
    script = function()
      return coroutine.create(function(co)
        vim.ui.input({
          prompt = 'Enter path or command to execute, for example: "${workspaceFolder}/src/foo.ps1" or "Invoke-Pester"',
          completion = "file",
        }, function(selected) coroutine.resume(co, selected) end)
      end)
    end,
  },
  {
    name = "PowerShell: Attach to PowerShell Host Process",
    type = "ps1",
    request = "attach",
    processId = "${command:pickProcess}",
  },
}
```

To use them, simply call `require('dap').continue()` inside of a `ps1` file.

**NOTE**: currently, debugging does not support launching an integrated terminal because of [PowerShell/PowerShellEditorServices#2164](https://github.com/PowerShell/PowerShellEditorServices/issues/2164)

## TODO

- [ ] Tests
