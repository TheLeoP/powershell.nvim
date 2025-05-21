---@alias powershell.command fun(command: lsp.Command, context: lsp.HandlerContext)

---@type table<string, powershell.command>
local M = {}

M["PowerShell.ShowCodeActionDocumentation"] = function(command)
  local rule_name = command.arguments[1] --[[@as string]]

  if not rule_name then return vim.notify "Cannot show documentation for code action, not rule_name was supplied." end

  if vim.startswith(rule_name, "PS") then rule_name = rule_name:sub(3) end

  vim.ui.open(("https://docs.microsoft.com/powershell/utility-modules/psscriptanalyzer/rules/%s"):format(rule_name))
end

return M
