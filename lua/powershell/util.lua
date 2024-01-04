local api = vim.api

local M = {}

M.noop = function() end

---@type table<integer, integer>
M.term_bufs = {}
--- client id -> term_win
---@type table<integer, integer>
M.term_wins = {}
--- client id -> term_channel
---@type table<integer, integer>
M.term_channels = {}
--- bufnr -> client id
---@type table<integer, integer>
M.clients_id = {}

---@param buf integer
---@return integer client_id for current buf
M.client_id = function(buf)
  local client_id = M.clients_id[buf]
  return client_id
end

---@param buf integer
---@return integer term_win for current buf
M.term_win = function(buf)
  local client_id = M.clients_id[buf]
  local term_win = M.term_wins[client_id]
  return term_win
end

---@param buf integer
---@return integer|nil term_buf for current buf
M.term_buf = function(buf)
  -- TODO: check before accessing
  local client_id = M.clients_id[buf]
  local term_buf = M.term_bufs[client_id]
  return term_buf
end

---@param client_id integer
---@return integer|nil term_buf for current buf
M.term_channel = function(client_id)
  -- TODO: check before accessing
  local term_channel = M.term_channels[client_id]
  return term_channel
end

---@type powershell.extension_command[]
M.extension_commands = {}

---@param has_range? boolean
---@return powershell.editor_context
M.get_editor_context = function(has_range)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0)) ---@type integer, integer

  local selectionRange = {
    start = vim.empty_dict(),
    ["end"] = vim.empty_dict(),
  }
  local mode = api.nvim_get_mode().mode ---@type string
  if mode == "v" or mode == "V" or mode == "\22" then M.exit_to_normal_mode() end

  if (mode == "v" or mode == "V" or mode == "\22") or (mode == "c" and has_range) then
    local start_row = vim.fn.line "'<" - 1
    local start_col = vim.fn.col "'<" - 1
    local end_row = vim.fn.line "'>" - 1
    local end_col = vim.fn.col "'>" - 1
    selectionRange.start = { character = start_col, line = start_row }
    selectionRange["end"] = { character = end_col, line = end_row }
  end

  ---@type powershell.editor_context
  local context = {
    currentFileContent = table.concat(api.nvim_buf_get_lines(0, 0, -1, true), "\n"),
    currentFileLanguage = vim.bo[0].filetype,
    currentFilePath = vim.fs.normalize(vim.api.nvim_buf_get_name(0)),
    cursorPosition = { character = col, line = row },
    selectionRange = selectionRange,
  }
  return context
end

M.exit_to_normal_mode = function()
  -- '\28\14' is an escaped version of `<C-\><C-n>`
  vim.cmd.normal { bang = true, args = { "\28\14" } }
end

---@param string string
---@return string[]
M.string_to_lines = function(string) return vim.split(string, "\r?\n") end

return M
