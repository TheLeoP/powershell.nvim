local api = vim.api

local util = require "powershell.util"

---@class powershell.user_config
---@field bundle_path string
---@field init_options table<string, any>|nil
---@field settings {powershell: powershell.lsp_settings}|nil
---@field capabilities lsp.ClientCapabilities|nil
---@field on_attach? function|nil
---@field shell? string|nil
---@field handlers table<string, powershell.handler>|nil
---@field root_dir nil|fun(buf: integer): string

---@class powershell.config
---@field bundle_path string
---@field init_options table<string, any>
---@field settings {powershell: powershell.lsp_settings}
---@field capabilities lsp.ClientCapabilities
---@field on_attach? function
---@field shell? string
---@field handlers table<string, powershell.handler>
---@field commands table<string, powershell.command>
---@field root_dir fun(buf: integer): string

---@class powershell.openFile
---@field filePath string
---@field preview boolean

---@class powershell.PowerShellAdditionalExePathSettings[]?
---@field versionName string
---@field exePath string

---@class powershell.ScriptAnalysisSettings
---@field enable boolean?
---@field settingsPath string

---@class powershell.DebuggingSettings
---@field createTemporaryIntegratedConsole boolean

---@class powershell.DeveloperSettings
---@field featureFlags string[]?
---@field powerShellExePath string?
---@field bundledModulesPath string?
---@field editorServicesLogLevel "Diagnostic"|"Verbose"|"Normal"|"Warning"|"Error"
---@field editorServicesWaitForDebugger boolean?
---@field powerShellExeIsWindowsDevBuild boolean?

---@class powershell.CodeFoldingSettings
---@field enable boolean?
---@field showLastLine boolean?

---@class powershell.CodeFormattingSettings
---@field autoCorrectAliases boolean?
---@field preset "Custom"|"Allman"|"OTBS"|"Stroustrup"?
---@field openBraceOnSameLine boolean?
---@field newLineAfterOpenBrace boolean?
---@field newLineAfterCloseBrace boolean?
---@field pipelineIndentationStyle "IncreaseIndentationForFirstPipeline"|"IncreaseIndentationAfterEveryPipeline"|"NoIndentation"?
---@field whitespaceBeforeOpenBrace boolean?
---@field whitespaceBeforeOpenParen boolean?
---@field whitespaceAroundOperator boolean?
---@field whitespaceAfterSeparator boolean?
---@field whitespaceBetweenParameters boolean?
---@field whitespaceInsideBrace boolean?
---@field addWhitespaceAroundPipe boolean?
---@field trimWhitespaceAroundPipe boolean?
---@field ignoreOneLineBlock boolean?
---@field alignPropertyValuePairs boolean?
---@field useConstantStrings boolean?
---@field useCorrectCasing boolean?

---@class powershell.IntegratedConsoleSettings
---@field showOnStartup boolean?
---@field focusConsoleOnExecute boolean?
---@field executeInCurrentScope boolean?

---@class powershell.BugReportingSettings
---@field project string

---@class powershell.lsp_settings
---@field powerShellAdditionalExePaths powershell.PowerShellAdditionalExePathSettings[]?
---@field powerShellDefaultVersion string?
---@field powerShellExePath string?
---@field bundledModulesPath string?
---@field startAutomatically boolean?
---@field useX86Host boolean?
---@field enableProfileLoading boolean?
---@field helpCompletion string?
---@field scriptAnalysis powershell.ScriptAnalysisSettings?
---@field debugging powershell.DebuggingSettings?
---@field developer powershell.DeveloperSettings?
---@field codeFolding powershell.CodeFoldingSettings?
---@field codeFormatting powershell.CodeFormattingSettings?
---@field integratedConsole powershell.IntegratedConsoleSettings?
---@field bugReporting powershell.BugReportingSettings?

---@class powershell
local M = {}

---@param user_config powershell.user_config
M.setup = function(user_config)
  vim.validate {
    bundle_path = { user_config.bundle_path, "string" },
    init_options = { user_config.init_options, "table", true },
    settings = { user_config.settings, "table", true },
    capabilities = { user_config.capabilities, "table", true },
    on_attach = { user_config.on_attach, "function", true },
    shell = { user_config.shell, "string", true },
    handlers = { user_config.handlers, "table", true },
    root_dir = { user_config.root_dir, "function", true },
  }

  if user_config then
    local config = require "powershell.config"
    config.config = vim.tbl_deep_extend("keep", user_config, config.default_config) --[[@as powershell.config]]
  end

  local ok = pcall(require, "dap")
  if ok then require("powershell.dap").setup() end
end

-- TODO: modify to allow multiple different seession_files
local temp_path = vim.fn.stdpath "cache"
local session_file_path = ("%s/powershell_es.session.json"):format(temp_path)
vim.fn.delete(session_file_path)

---@param bundle_path string
---@param shell string
---@return string[]
local function make_cmd(bundle_path, shell)
  --stylua: ignore
  return {
    shell,
    "-NoProfile",
    "-NonInteractive", ("%s/PowerShellEditorServices/Start-EditorServices.ps1"):format(bundle_path),
    "-HostName", "nvim",
    "-HostProfileId", "Neovim",
    "-HostVersion", "1.0.0",
    "-LogPath", ("%s/powershell_es.log"):format(temp_path),
    -- TODO: make this configurable
    "-LogLevel", "Normal",
    "-BundledModulesPath", ("%s"):format(bundle_path),
    "-LanguageServiceOnly",
    "-EnableConsoleRepl",
    "-SessionDetailsPath", session_file_path,
    "-AdditionalModules", "@()",
    "-FeatureFlags", "@()",
  }
end

---@param buf integer
---@param session_details powershell.session_details
---@return vim.lsp.ClientConfig|nil
local function get_lsp_config(buf, session_details)
  local config = require("powershell.config").config
  if not config.bundle_path then
    vim.notify("Powershell.nvim: there is no value configured for `bundle_path`.", vim.log.levels.ERROR)
    return
  end

  ---@type vim.lsp.ClientConfig
  local lsp_config = {
    name = "powershell_es",
    cmd = vim.lsp.rpc.connect(session_details.languageServicePipeName),
    capabilities = config.capabilities,
    on_attach = config.on_attach,
    settings = config.settings,
    init_options = config.init_options,
    handlers = config.handlers,
    commands = config.commands,
    root_dir = config.root_dir(buf),
  }
  return lsp_config
end

---@class powershell.session_details
---@field debugServicePipeName string?
---@field debugServiceTransport string?
---@field languageServicePipeName string?
---@field languageServiceTransport string?
---@field powerShellVersion string?
---@field status string?

--- root_dir -> sesssion_details
---@type table<string, powershell.session_details>
local session_details = {}

---@class powershell.lsp.dispatchers
---@field notification function
---@field server_request function
---@field on_exit function
---@field on_error function

---@class powershell.lsp.start_server
---@field request fun(method: string, params: table?, callbackfun: fun(err: lsp.ResponseError | nil, result: any), notify_reply_callback:function?)
---@field notify fun(method: string, params: any)
---@field is_closing function
---@field terminate function

---@return boolean
function M.is_term_open()
  local buf = api.nvim_get_current_buf()
  local term_win = util.term_win(buf)
  if not term_win then return false end

  local win_type = vim.fn.win_gettype(term_win)

  -- empty string window type corresponds to a normal window
  local win_open = win_type == "" or win_type == "popup"
  return win_open and api.nvim_win_get_buf(term_win) == util.term_buf(buf)
end

M.open_term = function()
  local bufnr = api.nvim_get_current_buf()
  local term_bufnr = util.term_buf(bufnr)
  if not term_bufnr then return vim.notify("Powershell.nvim: there is no terminal buffer", vim.log.levels.ERROR) end

  local client = util.clients_id[bufnr]

  --TODO: make this configurable
  vim.cmd.split()
  api.nvim_set_current_buf(term_bufnr)
  local term_win = api.nvim_get_current_win()
  util.term_wins[client] = term_win

  -- To toggle when inside terminal window
  if not util.clients_id[term_bufnr] then util.clients_id[term_bufnr] = client end
end

function M.close_term()
  local buf = api.nvim_get_current_buf()
  local term_win = util.term_win(buf)
  if not term_win then return vim.notify("Powershell.nvim: there is no terminal window", vim.log.levels.ERROR) end

  api.nvim_win_close(term_win, true)
end

M.toggle_term = function()
  if M.is_term_open() then
    M.close_term()
  else
    M.open_term()
  end
end

---@param buf integer
M.initialize_or_attach = function(buf)
  if vim.bo[buf].buftype == "nofile" then return end

  local bufname = api.nvim_buf_get_name(buf)
  if #bufname == 0 then return end

  local config = require("powershell.config").config
  local term_buf = util.term_buf(buf)

  local client_id = util.clients_id[buf]
  local term_channel = util.term_channels[client_id]
  if not term_buf or not term_channel then
    term_buf = api.nvim_create_buf(true, true)
    api.nvim_buf_call(term_buf, function()
      local cmd = make_cmd(config.bundle_path, config.shell)
      term_channel = vim.fn.jobstart(cmd, { term = true })
    end)
  end

  local root_dir = config.root_dir(buf)

  if session_details[root_dir] then
    local lsp_config = get_lsp_config(buf, session_details[root_dir])
    if lsp_config then vim.lsp.start(lsp_config, { bufnr = buf }) end
    return
  end

  util.wait_for_session_file(session_file_path, function(current_session_details, error_msg)
    if error_msg then return vim.notify(error_msg, vim.log.levels.ERROR) end

    local lsp_config = get_lsp_config(buf, current_session_details)
    if not lsp_config then return end

    local client = vim.lsp.start(lsp_config, { bufnr = buf })
    if not client then return vim.notify("LSP client has not been initialized", vim.log.levels.ERROR) end

    session_details[root_dir] = current_session_details
    util.clients_id[buf] = client
    util.term_bufs[client] = term_buf
    util.term_channels[client] = term_channel
  end)
end

M.eval = function()
  local buf = api.nvim_get_current_buf()
  local client_id = util.clients_id[buf]
  if not client_id then
    vim.notify(
      "There is no LSP client initialized by powershell.nvim attached to the current buffer.",
      vim.log.levels.WARN
    )
    return
  end
  local term_channel = assert(util.term_channels[client_id])

  local mode = api.nvim_get_mode().mode
  ---@type string[]?
  local lines
  if mode == "n" then
    lines = { api.nvim_get_current_line() }
  elseif mode == "v" or mode == "V" or mode == "\22" then
    vim.cmd.normal { args = { "\27" }, bang = true }

    local start_row = vim.fn.line "'<" - 1
    local start_col = vim.fn.col "'<" - 1
    local end_row = vim.fn.line "'>" - 1
    local end_col = vim.fn.col "'>" --[[@as integer]]

    lines = api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {})
  end
  vim
    .iter(lines)
    :map(function(line) return line .. "\r" end)
    :each(function(line) api.nvim_chan_send(term_channel, line) end)

  -- TODO: wait for response on https://github.com/PowerShell/PowerShellEditorServices/issues/2164
  -- local client = assert(vim.lsp.get_client_by_id(client_id))
  -- client.request("evaluate", { expression = text }, util.noop, 0)
end

return M
