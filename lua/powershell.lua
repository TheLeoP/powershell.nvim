local lsp = require "powershell.lsp"
local dap = require "powershell.dap"

local M = {}

M.eval = lsp.eval
M.eval_operator = lsp.eval_operator
M.setup = lsp.setup
M.toggle_term = lsp.toggle_term
M.initialize_or_attach = lsp.initialize_or_attach

M.toggle_debug_term = dap.toggle_debug_term

return M
