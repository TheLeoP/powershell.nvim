local api = vim.api
local iter = vim.iter

local util = require "powershell.util"

---@alias powershell.LogLevel "Trace" | "Debug" | "Information" | "Warning" | "Error" | "Critical" | "None"

---@class powershell.user_config
---@field shell string|nil
---@field bundle_path string
---@field feature_flags string[]|nil
---@field lsp_log_level powershell.LogLevel|nil
---@field init_options table<string, any>|nil
---@field settings {powershell: powershell.lsp_settings}|nil
---@field capabilities lsp.ClientCapabilities|nil
---@field on_attach? function|nil
---@field handlers table<string, powershell.handler>|nil
---@field root_dir nil|fun(buf: integer): string

---@class powershell.config
---@field shell string
---@field bundle_path string
---@field feature_flags string[]
---@field lsp_log_level powershell.LogLevel
---@field init_options table<string, any>
---@field settings {powershell: powershell.lsp_settings}
---@field capabilities lsp.ClientCapabilities
---@field on_attach? function
---@field handlers table<string, powershell.handler>
---@field commands table<string, powershell.command>
---@field root_dir fun(buf: integer): string

---@class powershell.openFile
---@field filePath string
---@field preview boolean

---@class powershell.ScriptAnalysisSettings
---@field enable boolean?
---@field settingsPath string

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

---@class powershell.lsp_settings
---@field powerShellDefaultVersion string?
---@field powerShellExePath string?
---@field bundledModulesPath string?
---@field startAutomatically boolean?
---@field useX86Host boolean?
---@field enableProfileLoading boolean?
---@field helpCompletion string?
---@field scriptAnalysis powershell.ScriptAnalysisSettings?
---@field codeFormatting powershell.CodeFormattingSettings?

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
session_file_path = vim.fs.normalize(session_file_path)
local log_file_path = ("%s/powershell_es.log"):format(temp_path)
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
    "-LanguageServiceOnly",
    "-EnableConsoleRepl",
    "-SessionDetailsPath", session_file_path,
    "-FeatureFlags", ("@(%s)"):format(table.concat(config.feature_flags, ', ')),
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

--- root_dir -> is_pending
---@type {[string]: boolean}
local is_pending = {}

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
  local current_buf = api.nvim_get_current_buf()
  local term_buf = util.term_buf(current_buf)
  local term_win = iter(api.nvim_tabpage_list_wins(0)):find(function(win)
    local buf = api.nvim_win_get_buf(win)
    return buf == term_buf
  end)
  if not term_win then return false end

  local win_type = vim.fn.win_gettype(term_win)

  -- empty string window type corresponds to a normal window
  return win_type == "" or win_type == "popup"
end

M.open_term = function()
  local buf = api.nvim_get_current_buf()
  local term_bufnr = util.term_buf(buf)
  if not term_bufnr then
    return vim.notify("Powershell.nvim: there is no terminal buffer for current buffer", vim.log.levels.ERROR)
  end

  local client = util.clients_id[buf]

  --TODO: make this configurable
  vim.cmd.split()
  api.nvim_set_current_buf(term_bufnr)

  -- To toggle when inside terminal window
  if not util.clients_id[term_bufnr] then util.clients_id[term_bufnr] = client end
end

function M.close_term()
  local current_buf = api.nvim_get_current_buf()
  local term_buf = util.term_buf(current_buf)
  local term_win = iter(api.nvim_tabpage_list_wins(0)):find(function(win)
    local buf = api.nvim_win_get_buf(win)
    return buf == term_buf
  end)
  if not term_win then
    return vim.notify("Powershell.nvim: there is no terminal window for current buffer", vim.log.levels.ERROR)
  end

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
  if bufname == "" then return end

  local config = require("powershell.config").config
  local root_dir = config.root_dir(buf)

  local session_details = util.all_session_details[root_dir]
  if session_details then
    local lsp_config = get_lsp_config(buf, session_details)
    if not lsp_config then return end
    local client = vim.lsp.start(lsp_config, { bufnr = buf })
    util.clients_id[buf] = client
    return
  end

  if is_pending[root_dir] then
    api.nvim_create_autocmd("User", {
      pattern = util.session_details_pattern:format(root_dir),
      callback = function(opts)
        local session_details = opts.data.session_details
        local lsp_config = get_lsp_config(buf, session_details)
        if not lsp_config then return end
        local client = vim.lsp.start(lsp_config, { bufnr = buf })
        util.clients_id[buf] = client
      end,
      once = true,
    })
    return
  end
  is_pending[root_dir] = true

  ---@type integer?
  local client_id = util.clients_id[buf]
  assert(not client_id)
  local term_buf = api.nvim_create_buf(false, false)
  local cmd = make_cmd(config)

  coroutine.wrap(function()
    local co = coroutine.running()
    vim.schedule(function()
      api.nvim_buf_call(term_buf, function()
        local term_channel = vim.fn.jobstart(cmd, { term = true })
        coroutine.resume(co, term_channel)
      end)
    end)
    local term_channel = coroutine.yield() ---@type integer
    api.nvim_exec_autocmds("User", {
      pattern = "powershell.nvim-term",
      data = {
        channel = term_channel,
        buf = term_buf,
      },
    })

    util.wait_for_session_file(
      session_file_path,
      function(current_session_details, error_msg) coroutine.resume(co, current_session_details, error_msg) end
    )
    local current_session_details, error_msg = coroutine.yield() ---@type powershell.session_details?, string?

    if error_msg then return vim.notify(error_msg, vim.log.levels.ERROR) end
    ---@cast current_session_details -nil

    is_pending[root_dir] = nil
    api.nvim_exec_autocmds("User", {
      pattern = util.session_details_pattern:format(root_dir),
      data = {
        session_details = current_session_details,
      },
    })
    local lsp_config = get_lsp_config(buf, current_session_details)
    if not lsp_config then return end

    client_id = vim.lsp.start(lsp_config, { bufnr = buf })
    if not client_id then return vim.notify("LSP client has not been initialized", vim.log.levels.ERROR) end

    util.all_session_details[root_dir] = current_session_details
    util.clients_id[buf] = client_id
    util.terms[client_id] = { buf = term_buf, channel = term_channel }
    api.nvim_create_autocmd("LspDetach", {
      callback = function(opts)
        if opts.data.client_id == client_id then
          util.clients_id[opts.buf] = nil
          util.terms[client_id] = nil

          local client = vim.lsp.get_client_by_id(client_id)
          if not client then return end
          local attached_buffers = iter(pairs(client.attached_buffers)):map(function(buf) return buf end):totable()
          if #attached_buffers == 1 and attached_buffers[1] == opts.buf then
            util.all_session_details[root_dir] = nil
            vim.schedule(function() api.nvim_buf_delete(term_buf, { force = true }) end)
          end

          return true
        end
      end,
      buffer = buf,
    })
  end)()
end

M.eval = function()
  local buf = api.nvim_get_current_buf()
  local client_id = util.clients_id[buf]
  if not client_id then
    return vim.notify(
      "There is no LSP client initialized by powershell.nvim attached to the current buffer.",
      vim.log.levels.WARN
    )
  end

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
  assert(lines)

  local client = assert(vim.lsp.get_client_by_id(client_id))
  client:request("evaluate", { expression = table.concat(lines, "\n") }, util.noop, 0)
end

function M._eval_operator_implementation(type)
  local buf = api.nvim_get_current_buf()
  local client_id = util.clients_id[buf]
  if not client_id then
    return vim.notify(
      "There is no LSP client initialized by powershell.nvim attached to the current buffer.",
      vim.log.levels.WARN
    )
  end

  local range_type = type == "line" and "V" or type == "char" and "v" or ""
  local lines = vim.fn.getregion(vim.fn.getpos "'[", vim.fn.getpos "']", { type = range_type })

  local client = assert(vim.lsp.get_client_by_id(client_id))
  client:request("evaluate", { expression = table.concat(lines, "\n") }, util.noop, 0)
end

function M.eval_operator()
  vim.o.operatorfunc = "v:lua.require'powershell.lsp'._eval_operator_implementation"
  return "g@"
end

return M
