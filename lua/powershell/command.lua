local api = vim.api
local iter = vim.iter

---@class powershell.editor_context
---@field currentFileContent string
---@field currentFileLanguage string
---@field currentFilePath string
---@field cursorPosition lsp.Position
---@field selectionRange lsp.Range

local util = require "powershell.util"

local M = {}

--- @alias powershell.command_opts {name: string, args: string, fargs: string[], bang: boolean, line1: number, line2: number, range: number, count: number, reg: string, mods: string, smods: string[]}

---@param arg_lead string
---@param cmd_line string
---@param _cursor_pos integer
---@return string[]
local complete = function(arg_lead, cmd_line, _cursor_pos)
  local number_of_arguments = #vim.split(cmd_line, " ")
  if number_of_arguments > 2 then return {} end

  return iter(util.extension_commands)
    :map(function(command) return command.name end)
    :filter(function(name) return vim.startswith(name, arg_lead) end)
    :totable()
end

M.create = function()
  api.nvim_buf_create_user_command(
    0,
    "Powershell",
    ---@param opts powershell.command_opts
    function(opts)
      local command = opts.fargs[1]
      if not iter(util.extension_commands):map(function(c) return c.name end):find(command) then
        return vim.notify(("The command %s is not registered"):format(command), vim.log.levels.ERROR)
      end

      local buf = api.nvim_get_current_buf()
      local client_id = assert(util.client_id(buf))
      local client = assert(vim.lsp.get_client_by_id(client_id))
      local context = util.get_editor_context(opts.range ~= 0)
      client:request("powerShell/invokeExtensionCommand", { name = command, Context = context }, util.noop, 0)
    end,
    {
      nargs = "+",
      range = true,
      complete = complete,
    }
  )
end

return M
