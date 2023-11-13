local uv = vim.loop
local pipes = require "powershell.pipe"

---@class powershell.config
local default_config = {
  on_attach = function() end,
  capabilities = vim.lsp.protocol.make_client_capabilities(),
  bundle_path = "",
  init_options = vim.empty_dict(),
  settings = vim.empty_dict(),
  shell = "pwsh",
}

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
---@field autoCorrectAliases boolean
---@field preset "Custom"|"Allman"|"OTBS"|"Stroustrup"
---@field openBraceOnSameLine boolean
---@field newLineAfterOpenBrace boolean
---@field newLineAfterCloseBrace boolean
---@field pipelineIndentationStyle "IncreaseIndentationForFirstPipeline"|"IncreaseIndentationAfterEveryPipeline"|"NoIndentation"
---@field whitespaceBeforeOpenBrace boolean
---@field whitespaceBeforeOpenParen boolean
---@field whitespaceAroundOperator boolean
---@field whitespaceAfterSeparator boolean
---@field whitespaceBetweenParameters boolean
---@field whitespaceInsideBrace boolean
---@field addWhitespaceAroundPipe boolean
---@field trimWhitespaceAroundPipe boolean
---@field ignoreOneLineBlock boolean
---@field alignPropertyValuePairs boolean
---@field useConstantStrings boolean
---@field useCorrectCasing boolean

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
---@field helpCompletion string
---@field scriptAnalysis powershell.ScriptAnalysisSettings?
---@field debugging powershell.DebuggingSettings?
---@field developer powershell.DeveloperSettings?
---@field codeFolding powershell.CodeFoldingSettings?
---@field codeFormatting powershell.CodeFormattingSettings?
---@field integratedConsole powershell.IntegratedConsoleSettings?
---@field bugReporting powershell.BugReportingSettings?

---@class powershell.lsp_config
---@field cmd string[]
---@field capabilities table
---@field handlers table<string, function>?
---@field settings powershell.lsp_settings
---@field commands table<string, function>?
---@field init_options table<string, any>
---@field name string
---@field on_attach function?
---@field root_dir string

---@class powershell
local M = {}

---@type powershell.config
M.config = default_config

---@param args powershell.config?
M.setup = function(args)
  if args then M.config = vim.tbl_deep_extend("force", M.config, args) end

  local ok, dap = pcall(require, "dap")
  if ok then
    dap.adapters.powershell = function(callback)
      callback {
        type = "pipe",
        pipe = M._session_details.debugServicePipeName,
      }
    end
    dap.configurations.ps1 = {
      {
        name = "PowerShell: Launch Current File",
        type = "powershell",
        request = "launch",
        script = "${file}",
      },
      {
        name = "PowerShell: Attach to PowerShell Host Process",
        type = "powershell",
        request = "attach",
        runspaceId = 1,
      },
      {
        name = "PowerShell: Run Pester Tests",
        type = "powershell",
        request = "launch",
        script = "Invoke-Pester",
        createTemporaryIntegratedConsole = true,
        attachDotnetDebugger = true,
      },
      {
        name = "PowerShell: Interactive Session",
        type = "powershell",
        request = "launch",
      },
    }
  end
end

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
    "-EnableConsoleRepl",
    "-SessionDetailsPath", session_file_path,
    "-AdditionalModules", "@()",
    "-FeatureFlags", "@()",
  }
end

---@return powershell.lsp_config|nil
local function get_lsp_config()
  if not M.config.bundle_path then
    vim.notify("Powershell.nvim: there is no value configured for `bundle_path`.", vim.log.levels.ERROR)
    return
  end

  ---@type powershell.lsp_config
  local lsp_config = {
    name = "powershell_es",
    cmd = M.domain_socket_connect(M._session_details.languageServicePipeName),
    capabilities = M.config.capabilities or default_config.capabilities,
    on_attach = M.config.on_attach or default_config.on_attach,
    settings = M.config.settings or default_config.settings,
    init_options = M.config.init_options or default_config.init_options,
    root_dir = vim.fs.dirname(
      vim.fs.find({ ".git" }, { upward = true, path = vim.fs.dirname(vim.api.nvim_buf_get_name(0)) })[1]
    ),
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

---@param file_path string
---@param callback fun(session_details: powershell.session_details?, error_msg: string?)
local function wait_for_session_file(file_path, callback)
  ---@param remaining_tries integer
  ---@param delay_miliseconds integer
  local function inner_try_func(remaining_tries, delay_miliseconds)
    if remaining_tries == 0 then
      vim.notify(
        ("Powershell.nvim: the session file on path `%s` could not be found."):format(file_path),
        vim.log.levels.ERROR
      )
    elseif not (vim.fn.filereadable(file_path) == 1) then
      vim.defer_fn(function() inner_try_func(remaining_tries - 1, delay_miliseconds) end, delay_miliseconds)
    else
      local f, error_msg = io.open(file_path)
      if not f then
        vim.notify(
          ("Powershell.nvim: %s"):format(
            error_msg or ("the session file on path `%s` could not be read."):format(file_path)
          ),
          vim.log.levels.ERROR
        )
        return
      end
      local session_file = vim.json.decode(f:read "*a")
      f:close()
      vim.fn.delete(file_path)

      callback(session_file)
    end
  end
  inner_try_func(60, 2000)
end

---@type powershell.session_details|nil
M._session_details = nil

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

---@param pipe_path  string
---@return fun(dispatchers: powershell.lsp.dispatchers): powershell.lsp.start_server?
function M.domain_socket_connect(pipe_path)
  return function(dispatchers)
    dispatchers = pipes.merge_dispatchers(dispatchers)
    local pipe, err_name, err_message = uv.new_pipe(false)
    if not pipe then
      vim.notify(
        ("Powershell.nvim: error %s, %s"):format(vim.inspect(err_name), vim.inspect(err_message)),
        vim.log.levels.ERROR
      )
      return
    end
    local closing = false
    local transport = {
      write = vim.schedule_wrap(function(msg) pipe:write(msg) end),
      is_closing = function() return closing end,
      terminate = function()
        if not closing then
          closing = true
          pipe:shutdown()
          pipe:close()
          dispatchers.on_exit(0, 0)
        end
      end,
    }
    local client = pipes.new_client(dispatchers, transport)
    pipe:connect(pipe_path, function(err)
      if err then
        vim.schedule(
          function()
            vim.notify(
              string.format("Could not connect to :%s, reason: %s", pipe_path, vim.inspect(err)),
              vim.log.levels.WARN
            )
          end
        )
        return
      end
      local handle_body = function(body) client:handle_body(body) end
      pipe:read_start(
        pipes.create_read_loop(
          handle_body,
          transport.terminate,
          function(read_err) client:on_error(pipes.client_errors.READ_ERROR, read_err) end
        )
      )
    end)

    return pipes.public_client(client)
  end
end

--- client id -> term_buf
---@type table<integer, integer>
local term_bufs = {}
--- client id -> term_win
---@type table<integer, integer>
local term_wins = {}

--- bufnr -> client id
---@type table<integer, integer>
local clients = {}

---@return integer term_win for current buf
M.term_win = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local client = clients[bufnr]
  local term_win = term_wins[client]
  return term_win
end

---@return integer|nil term_buf for current buf
M.term_buf = function()
  local bufnr = vim.api.nvim_get_current_buf()
  -- TODO: check before accessing
  local client = clients[bufnr]
  local term_buf = term_bufs[client]
  return term_buf
end

--- @return boolean
M.is_term_open = function()
  local term_win = M.term_win()
  if not term_win then return false end

  local win_type = vim.fn.win_gettype(term_win)

  -- empty string window type corresponds to a normal window
  local win_open = win_type == "" or win_type == "popup"
  return win_open and vim.api.nvim_win_get_buf(term_win) == M.term_buf()
end

M.open_term = function()
  local term_bufnr = M.term_buf()
  if term_bufnr then
    local bufnr = vim.api.nvim_get_current_buf()
    local client = clients[bufnr]

    --TODO: make this configurable
    vim.cmd.split()
    vim.api.nvim_set_current_buf(term_bufnr)
    local term_win = vim.api.nvim_get_current_win()
    term_wins[client] = term_win

    -- To toggle when inside terminal window
    if not clients[term_bufnr] then clients[term_bufnr] = client end
  else
    vim.notify("Powershell.nvim: there is no terminal buffer", vim.log.levels.ERROR)
  end
end

M.close_term = function()
  local term_win = M.term_win()
  if term_win then
    vim.api.nvim_win_close(term_win, true)
  else
    vim.notify("Powershell.nvim: there is no terminal window", vim.log.levels.ERROR)
  end
end

M.toggle_term = function()
  if M.is_term_open() then
    M.close_term()
  else
    M.open_term()
  end
end

M.initialize_or_attach = function()
  local term_buf = M.term_buf()
  if not term_buf then
    term_buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_call(term_buf, function()
      local cmd = make_cmd(M.config.bundle_path, M.config.shell)
      vim.fn.termopen(cmd)
    end)
  end

  local buf = vim.api.nvim_get_current_buf()
  wait_for_session_file(session_file_path, function(session_details, error_msg)
    if session_details then
      M._session_details = session_details
      local lsp_config = get_lsp_config()
      if lsp_config then
        local client = vim.lsp.start(lsp_config)
        if client then
          clients[buf] = client
          term_bufs[client] = term_buf
        end
      end
    else
      vim.notify(error_msg, vim.log.levels.ERROR)
    end
  end)
end

local noop = function() end
M.eval = function()
  local buf = vim.api.nvim_get_current_buf()
  local client_id = clients[buf]
  if not client_id then
    vim.notify(
      "There is no LSP client initialized by powershell.nvim attached to the current buffer.",
      vim.log.levels.WARN
    )
    return
  end
  local client = vim.lsp.get_client_by_id(client_id)

  local mode = vim.api.nvim_get_mode().mode
  ---@type string
  local text
  if mode == "n" then
    text = vim.api.nvim_get_current_line()
  elseif mode == "v" or mode == "V" or mode == "\22" then
    vim.cmd.normal { args = { "\27" }, bang = true }

    local start_row = vim.fn.line "'<" - 1
    local start_col = vim.fn.col "'<" - 1
    local end_row = vim.fn.line "'>" - 1
    local end_col = vim.fn.col "'>"

    text = table.concat(vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {}), "\n")
  end

  client.request("evaluate", { expression = text }, noop, 0)
end

return M
