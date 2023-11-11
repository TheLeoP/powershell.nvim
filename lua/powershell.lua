local uv = vim.loop
local validate, schedule, schedule_wrap = vim.validate, vim.schedule, vim.schedule_wrap
local protocol = vim.lsp.protocol
local log = require("vim.lsp.log")

local client_errors = {
	INVALID_SERVER_MESSAGE = 1,
	INVALID_SERVER_JSON = 2,
	NO_RESULT_CALLBACK_FOUND = 3,
	READ_ERROR = 4,
	NOTIFICATION_HANDLER_ERROR = 5,
	SERVER_REQUEST_HANDLER_ERROR = 6,
	SERVER_RESULT_CALLBACK_ERROR = 7,
}

---@class powershell.config
local default_config = {
	on_attach = function() end,
	capabilities = vim.lsp.protocol.make_client_capabilities(),
	bundle_path = "",
	init_options = {},
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
	if args then
		M.config = vim.tbl_deep_extend("force", M.config, args)
	end
end

local temp_path = vim.fn.stdpath("cache")
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
    "-LogLevel", "Diagnostic",
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
		vim.notify("Powershell.nvim: Error", vim.log.levels.ERROR)
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
			-- TODO: error
			vim.notify("error", vim.log.levels.ERROR)
		elseif not (vim.fn.filereadable(file_path) == 1) then
			vim.defer_fn(function()
				inner_try_func(remaining_tries - 1, delay_miliseconds)
			end, delay_miliseconds)
		else
			local f, error_msg = io.open(file_path)
			if not f then
				vim.notify(error_msg or "Error", vim.log.levels.ERROR)
				return
			end
			local session_file = vim.json.decode(f:read("*a"))
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

-- TODO: copied from neovim internals
local function request_parser_loop()
	local buffer = "" -- only for header part
	while true do
		-- A message can only be complete if it has a double CRLF and also the full
		-- payload, so first let's check for the CRLFs
		local start, finish = buffer:find("\r\n\r\n", 1, true)
		-- Start parsing the headers
		if start then
			-- This is a workaround for servers sending initial garbage before
			-- sending headers, such as if a bash script sends stdout. It assumes
			-- that we know all of the headers ahead of time. At this moment, the
			-- only valid headers start with "Content-*", so that's the thing we will
			-- be searching for.
			-- TODO(ashkan) I'd like to remove this, but it seems permanent :(
			local buffer_start = buffer:find(header_start_pattern)
			local headers = parse_headers(buffer:sub(buffer_start, start - 1))
			local content_length = headers.content_length
			-- Use table instead of just string to buffer the message. It prevents
			-- a ton of strings allocating.
			-- ref. http://www.lua.org/pil/11.6.html
			local body_chunks = { buffer:sub(finish + 1) }
			local body_length = #body_chunks[1]
			-- Keep waiting for data until we have enough.
			while body_length < content_length do
				local chunk = coroutine.yield() or error("Expected more data for the body. The server may have died.") -- TODO hmm.
				table.insert(body_chunks, chunk)
				body_length = body_length + #chunk
			end
			local last_chunk = body_chunks[#body_chunks]

			body_chunks[#body_chunks] = last_chunk:sub(1, content_length - body_length - 1)
			local rest = ""
			if body_length > content_length then
				rest = last_chunk:sub(content_length - body_length)
			end
			local body = table.concat(body_chunks)
			-- Yield our data.
			buffer = rest
				.. (
					coroutine.yield(headers, body) or error(
						"Expected more data for the body. The server may have died."
					)
				) -- TODO hmm.
		else
			-- Get more data since we don't have enough.
			buffer = buffer
				.. (coroutine.yield() or error("Expected more data for the header. The server may have died.")) -- TODO hmm.
		end
	end
end

-- TODO: copied from neovim internals
local function create_read_loop(handle_body, on_no_chunk, on_error, notify, pipe)
	local parse_chunk = coroutine.wrap(request_parser_loop)
	parse_chunk()
	return function(err, chunk)
		if err then
			on_error(err)
			return
		end

		if not chunk then
			if on_no_chunk then
				on_no_chunk()
			end
			return
		end

		while true do
			local headers, body = parse_chunk(chunk)
			if headers then
				handle_body(body, on_error, notify, pipe)
				chunk = ""
			else
				break
			end
		end
	end
end

---@param err (table) The error object
---@return (string) #The formatted error message
local function format_rpc_error(err)
	validate({
		err = { err, "t" },
	})

	-- There is ErrorCodes in the LSP specification,
	-- but in ResponseError.code it is not used and the actual type is number.
	---@type string
	local code
	if protocol.ErrorCodes[err.code] then
		code = string.format("code_name = %s,", protocol.ErrorCodes[err.code])
	else
		code = string.format("code_name = unknown, code = %s,", err.code)
	end

	local message_parts = { "RPC[Error]", code }
	if err.message then
		table.insert(message_parts, "message =")
		table.insert(message_parts, string.format("%q", err.message))
	end
	if err.data then
		table.insert(message_parts, "data =")
		table.insert(message_parts, vim.inspect(err.data))
	end
	return table.concat(message_parts, " ")
end

---@param code integer RPC error code defined in `vim.lsp.protocol.ErrorCodes`
---@param message string|nil arbitrary message to send to server
---@param data any|nil arbitrary data to send to server
local function rpc_response_error(code, message, data)
	-- TODO should this error or just pick a sane error (like InternalError)?
	local code_name = assert(protocol.ErrorCodes[code], "Invalid RPC error code")
	return setmetatable({
		code = code,
		message = message or code_name,
		data = data,
	}, {
		__tostring = format_rpc_error,
	})
end

local function pcall_handler(errkind, status, head, on_error, ...)
	if not status then
		on_error(errkind, head, ...)
		return status, head
	end
	return status, head, ...
end
local function try_call(on_error, errkind, fn, ...)
	return pcall_handler(on_error, errkind, pcall(fn, ...))
end

local function handle_body(body, on_error, notify, pipe)
	local ok, decoded = pcall(vim.json.decode, body, { luanil = { object = true } })
	if not ok then
		on_error(client_errors.INVALID_SERVER_JSON, decoded)
		return
	end

	local _ = log.debug() and log.debug("pipe.receive", decoded)
	if type(decoded.method) == "string" and decoded.id then
		local err
		-- Schedule here so that the users functions don't trigger an error and
		-- we can still use the result.
		schedule(function()
			coroutine.wrap(function()
				local status, result
				status, result, err = try_call(
					on_error,
					client_errors.SERVER_REQUEST_HANDLER_ERROR,
					self.dispatchers.server_request,
					decoded.method,
					decoded.params
				)
				local _ = log.debug()
					and log.debug("server_request: callback result", { status = status, result = result, err = err })
				if status then
					if result == nil and err == nil then
						error(
							string.format(
								"method %q: either a result or an error must be sent to the server in response",
								decoded.method
							)
						)
					end
					if err then
						assert(
							type(err) == "table",
							"err must be a table. Use rpc_response_error to help format errors."
						)
						local code_name = assert(
							protocol.ErrorCodes[err.code],
							"Errors must use protocol.ErrorCodes. Use rpc_response_error to help format errors."
						)
						err.message = err.message or code_name
					end
				else
					-- On an exception, result will contain the error message.
					err = rpc_response_error(protocol.ErrorCodes.InternalError, result)
					result = nil
				end
				local encoded = vim.json.encode({
					id = decoded.id,
					jsonrpc = "2.0",
					error = err,
					result = result,
				}) --[[@as string]]
				pipe:write(encoded)
			end)()
		end)
	elseif type(decoded.method) == "string" then
		-- Notification
		try_call(on_error, client_errors.NOTIFICATION_HANDLER_ERROR, notify, decoded.method, decoded.params)
	else
		-- Invalid server message
		on_error(client_errors.INVALID_SERVER_MESSAGE, decoded)
	end
end

---@param pipe_path  string
---@return fun(dispatchers: powershell.lsp.dispatchers): powershell.lsp.start_server?
function M.domain_socket_connect(pipe_path)
	local message_index = 1
	return function(dispatchers)
		local is_closing = false

		local pipe = uv.new_pipe()
		if not pipe then
			vim.notify("Error", vim.log.levels.ERROR)
			return
		end
		local terminate = function()
			if not is_closing then
				is_closing = true
				pipe:close()
				dispatchers.on_exit(0, 0)
			end
		end
		local notify = function(method, params)
			local encoded = vim.json.encode({
				jsonrpc = "2.0",
				method = method,
				params = params,
			}) --[[@as string]]
			pipe:write(encoded)
		end

		pipe:connect(pipe_path, function(err)
			if err then
				vim.schedule(function()
					vim.notify(
						string.format("Could not connect to %s, reason: %s", pipe_path, vim.inspect(err)),
						vim.log.levels.WARN
					)
				end)
				return
			end
			pipe:read_start(create_read_loop(handle_body, terminate, function(read_err)
				dispatchers.on_error(client_errors.READ_ERROR, read_err)
			end, notify, pipe))
		end)

		---@type powershell.lsp.start_server
		local start_server = {
			request = function(method, params, callback, notify_reply_callback)
				validate({
					callback = { callback, "f" },
					notify_reply_callback = { notify_reply_callback, "f", true },
				})
				local encoded = vim.json.encode({
					id = message_index,
					jsonrpc = "2.0",
					method = method,
					params = params,
				}) --[[@as string]]
				message_index = message_index + 1
				pipe:write(encoded)
			end,
			notify = notify,
			is_closing = function()
				return is_closing
			end,
			terminate = terminate,
		}
		return start_server
	end
end

---@type integer?
local term_buf
---@type integer?
local term_win

--- @return boolean
M.is_open_term = function()
	if not term_win then
		return false
	end

	local win_type = vim.fn.win_gettype(term_win)
	-- empty string window type corresponds to a normal window
	local win_open = win_type == "" or win_type == "popup"
	return win_open and vim.api.nvim_win_get_buf(term_win) == term_buf
end

M.open_term = function()
	if term_buf then
		--TODO: make this configurable
		vim.cmd.split()
		vim.api.nvim_set_current_buf(term_buf)
		term_win = vim.api.nvim_get_current_win()
	else
		vim.notify("Error", vim.log.levels.ERROR)
	end
end

M.close_term = function()
	if term_win then
		vim.api.nvim_win_close(term_win, true)
	else
		vim.notify("Error", vim.log.levels.ERROR)
	end
end

M.toggle_term = function()
	if M.is_open_term() then
		M.close_term()
	else
		M.open_term()
	end
end

M.initialize_or_attach = function()
	if not term_buf then
		term_buf = vim.api.nvim_create_buf(true, true)
		vim.api.nvim_buf_call(term_buf, function()
			local cmd = make_cmd(M.config.bundle_path, M.config.shell)
			vim.fn.termopen(cmd)
		end)
	end

	wait_for_session_file(session_file_path, function(session_details, error_msg)
		if session_details then
			M._session_details = session_details
			local lsp_config = get_lsp_config()
			if lsp_config then
				vim.lsp.start(lsp_config)
			end
		else
			vim.notify(error_msg, vim.log.levels.ERROR)
		end
	end)
end

return M
