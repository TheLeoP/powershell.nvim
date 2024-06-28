local api = vim.api
local util = require "powershell.util"

local M = {}

-- TODO: modify to allow multiple different seession_files
local temp_path = vim.fn.stdpath "cache"
local session_file_path = ("%s/powershell_es.temp_session.json"):format(temp_path)
session_file_path = vim.fs.normalize(session_file_path)
local log_file_path = ("%s/powershell_es.temp.log"):format(temp_path)
log_file_path = vim.fs.normalize(log_file_path)
vim.fn.delete(session_file_path)

---@param bundle_path string
---@return string[]
local function make_cmd(bundle_path)
  local file = ("%s/PowerShellEditorServices/Start-EditorServices.ps1"):format(bundle_path)
  file = vim.fs.normalize(file)
  --stylua: ignore
  return {
    "pwsh",
    "-NoLogo",
    "-NoProfile",
    "-NonInteractive",
    "-File", file,
    "-HostName", "nvim",
    "-HostProfileId", "Neovim",
    "-HostVersion", "1.0.0",
    "-LogPath", log_file_path,
    -- TODO: make this configurable
    "-LogLevel", "Normal",
    "-BundledModulesPath", ("%s"):format(bundle_path),
    "-DebugServiceOnly",
    -- TODO: wait for response on https://github.com/PowerShell/PowerShellEditorServices/issues/2164
    -- "-EnableConsoleRepl",
    "-SessionDetailsPath", session_file_path,
  }
end

function M.setup()
  local dap = require "dap"
  local config = require("powershell.config").config

  dap.adapters.powershell_no_term = function(on_config)
    local cmd = make_cmd(config.bundle_path)
    vim.system(cmd)
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
      name = "PowerShell: Launch Current File (no term)",
      type = "powershell_no_term",
      request = "launch",
      script = "${file}",
    },
  }
end

return M
