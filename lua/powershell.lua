local lsp = require "powershell.lsp"

local M = {}

M.eval = lsp.eval
M.setup = lsp.setup
M.toggle_term = lsp.toggle_term
M.initialize_or_attach = lsp.initialize_or_attach

return M
