local api = vim.api
local iter = vim.iter
local util = require "powershell.util"

local M = {}

-- TODO: modify to allow multiple different session_files
local temp_path = vim.fn.stdpath "cache"
local session_file_path = ("%s/powershell_es.temp_session.json"):format(temp_path)
session_file_path = vim.fs.normalize(session_file_path)
local log_file_path = ("%s/powershell_es.temp.log"):format(temp_path)
log_file_path = vim.fs.normalize(log_file_path)

---@param config powershell.config
---@return string[]
local function make_cmd(config)
  local file = ("%s/PowerShellEditorServices/Start-EditorServices.ps1"):format(config.bundle_path)
  file = vim.fs.normalize(file)
  --stylua: ignore
  return {
    config.shell,
    "-NoLogo",
    "-NoProfile",
    "-NonInteractive",
    "-File", file,
    "-HostName", "nvim",
    "-HostProfileId", "Neovim",
    "-HostVersion", "1.0.0",
    "-LogPath", log_file_path,
    "-LogLevel", config.lsp_log_level,
    "-BundledModulesPath", config.bundle_path,
    "-DebugServiceOnly",
    "-EnableConsoleRepl",
    "-SessionDetailsPath", session_file_path,
  }
end

local dap_term_buf ---@type integer?
local dap_term_channel ---@type integer?

---@return boolean
local function is_term_open()
  local term_win = iter(api.nvim_tabpage_list_wins(0)):find(function(win)
    local buf = api.nvim_win_get_buf(win)
    return buf == dap_term_buf
  end)
  if not term_win then return false end

  local win_type = vim.fn.win_gettype(term_win)

  -- empty string window type corresponds to a normal window
  return win_type == "" or win_type == "popup"
end

local function close_term()
  local term_win = iter(api.nvim_tabpage_list_wins(0)):find(function(win)
    local buf = api.nvim_win_get_buf(win)
    return buf == dap_term_buf
  end)
  if not term_win then return vim.notify("Powershell.nvim: there is no debug terminal window", vim.log.levels.ERROR) end

  api.nvim_win_close(term_win, true)
end

local function open_term()
  if not dap_term_buf then
    return vim.notify("Powershell.nvim: there is no debug terminal buffer", vim.log.levels.ERROR)
  end

  --TODO: make this configurable
  vim.cmd.split()
  api.nvim_set_current_buf(dap_term_buf)
end

function M.setup()
  local dap = require "dap"
  local config = require("powershell.config").config

  dap.adapters.ps1 = function(on_config)
    local cmd = make_cmd(config)
    dap_term_buf = api.nvim_create_buf(false, false)
    vim.api.nvim_buf_call(dap_term_buf, function()
      dap_term_channel = vim.fn.jobstart(cmd, { term = true })
      api.nvim_exec_autocmds("User", {
        pattern = "powershell.nvim-debug_term",
        data = {
          channel = dap_term_channel,
          buf = dap_term_buf,
        },
      })
    end)
    util.wait_for_session_file(session_file_path, function(current_session_details, error_msg)
      if error_msg then return vim.notify(error_msg, vim.log.levels.ERROR) end

      on_config {
        type = "pipe",
        pipe = current_session_details.debugServicePipeName,
      }
    end)
  end
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

  local key = "powershell.nvim"
  dap.listeners.after.initialize[key] = function(session)
    session.on_close[key] = function()
      if is_term_open() then close_term() end
      if dap_term_buf then api.nvim_buf_delete(dap_term_buf, { force = true }) end
      dap_term_channel = nil
      dap_term_buf = nil
    end
  end
  dap.listeners.after["event_powerShell/sendKeyPress"][key] = function()
    if not dap_term_channel then return end
    -- any char can be send, `p` is the one used by the VSCode extension
    api.nvim_chan_send(dap_term_channel, "p")
  end
end

function M.toggle_debug_term()
  if is_term_open() then
    close_term()
  else
    open_term()
  end
end

return M
