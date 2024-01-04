local api = vim.api

local util = require "powershell.util"
local extension_commands = util.extension_commands

--HACK: This isn't used, but it's necesary to send a response
local ERROR_ = 0
local OK_ = 1

---@alias powershell.handler fun(err?: table, result?: table, ctx: lsp.HandlerContext): integer|table?

---@type table<string, powershell.handler>
local M = {}

---@class powershell.extension_command
---@field displayName string
---@field name string

---@param result powershell.extension_command
M["powerShell/extensionCommandAdded"] = function(err, result, ctx)
  if err or not result then return end
  table.insert(extension_commands, result)
end

M["editor/getEditorContext"] = function(err, result, ctx)
  if err then return end
  return util.get_editor_context()
end

---@class powershell.insert_text
---@field insertRange lsp.Range
---@field filePath string URI
---@field insertText string

---@param result powershell.insert_text
M["editor/insertText"] = function(err, result, ctx)
  if err then return ERROR_ end
  local start = result.insertRange.start
  local end_ = result.insertRange["end"]
  if start.character == 0 and start.line == 0 and end_.character == 0 and end_.line == 0 then return ERROR_ end

  local bufnr = vim.uri_to_bufnr(result.filePath)

  api.nvim_buf_set_text(
    bufnr,
    start.line,
    start.character,
    end_.line,
    end_.character,
    util.string_to_lines(result.insertText)
  )

  return OK_
end

---@class powershell.set_selection
---@field selectionRange lsp.Range

---@param result powershell.set_selection
M["editor/setSelection"] = function(err, result, ctx)
  if err or not result or not result.selectionRange then return end

  util.exit_to_normal_mode()

  local start = result.selectionRange.start
  local end_ = result.selectionRange["end"]

  -- Open enough folds to show left and right edges
  api.nvim_win_set_cursor(0, { start.line + 1, start.character })
  vim.cmd "normal! zv"
  api.nvim_win_set_cursor(0, { end_.line + 1, math.max(end_.character - 1, 0) })
  vim.cmd "normal! zv"

  -- Respect exclusive selection
  if vim.o.selection == "exclusive" then vim.cmd "normal! l" end

  -- Start selection
  vim.cmd "normal! v"
  api.nvim_win_set_cursor(0, { start.line + 1, start.character })

  return OK_
end

---@param result string
M["editor/newFile"] = function(err, result, ctx)
  if err or not result then return end
  -- TODO: make configurable
  vim.cmd.new()
  api.nvim_buf_set_lines(0, 0, -1, true, util.string_to_lines(result))
  vim.cmd [[set filetype=ps1]]

  return OK_
end

---@param result? powershell.openFile
M["editor/openFile"] = function(err, result, ctx)
  -- TODO: handle relative directories (?)
  if err or not result or result.filePath == "" then return ERROR_ end
  if result.preview then
    vim.cmd.pedit(result.filePath)
  else
    -- TODO: make configurable
    vim.cmd.split()
    vim.cmd.edit(result.filePath)
  end
  return OK_
end

---@param result string
M["editor/closeFile"] = function(err, result, ctx)
  if err or not result then return ERROR_ end
  local bufnr = vim.fn.bufnr(result)
  if bufnr == -1 then return ERROR_ end

  local ok = pcall(api.nvim_buf_delete, bufnr, { unload = true })
  if not ok then return ERROR_ end

  return OK_
end

---@class powershell.save_file
---@field filePath string
---@field newPath? string

---@param result powershell.save_file
M["editor/saveFile"] = function(err, result, ctx)
  if err or not result then return ERROR_ end

  -- TODO: handle URI?

  local bufnr = vim.fn.bufnr(result.filePath)
  if not bufnr then return ERROR_ end

  if result.newPath then
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, true)
    --TODO: do not use new?
    vim.cmd.new(result.newPath)
    api.nvim_buf_set_lines(0, 0, -1, true, lines)
    vim.cmd.update()
  else
    api.nvim_buf_call(bufnr, function() vim.cmd.update() end)
  end

  return OK_
end

---@param result string
M["editor/showInformationMessage"] = function(err, result, ctx)
  if err or not result then return ERROR_ end

  vim.notify(result)

  return OK_
end

---@param result string
M["editor/showErrorMessage"] = function(err, result, ctx)
  if err or not result then return ERROR_ end

  vim.notify(result, vim.log.levels.ERROR)

  return OK_
end

---@param result string
M["editor/showWarningMessage"] = function(err, result, ctx)
  if err or not result then return ERROR_ end

  vim.notify(result, vim.log.levels.WARN)

  return OK_
end

---@class powershell.set_status_bar_message
---@field message string
---@field timeout? integer

---@param result powershell.set_status_bar_message
M["editor/setStatusBarMessage"] = function(err, result, ctx)
  if err or not result then return ERROR_ end

  vim.notify(result.message, nil, { timeout = result.timeout })

  return OK_
end

M["editor/clearTerminal"] = function(err, result, ctx)
  if err then return end

  local term_channel = assert(util.term_channel(ctx.client_id))
  api.nvim_chan_send(term_channel, "[System.Console]::Clear()\r")
end

return M
