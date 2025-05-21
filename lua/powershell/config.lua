local api = vim.api
local fs = vim.fs
local base_handlers = require "powershell.handlers"
local base_commands = require "powershell.commands"

local M = {}

---@type powershell.config
M.default_config = {
  capabilities = vim.lsp.protocol.make_client_capabilities(),
  bundle_path = "",
  init_options = vim.empty_dict() --[[@as table]],
  settings = vim.empty_dict() --[[@as table]],
  shell = "pwsh",
  handlers = base_handlers,
  commands = base_commands,
  root_dir = function(buf)
    local current_file_dir = fs.dirname(api.nvim_buf_get_name(buf))
    return fs.dirname(fs.find({ ".git" }, { upward = true, path = current_file_dir })[1]) or current_file_dir
  end,
}

---@type powershell.config
M.config = nil

return M
