local api = vim.api
local group = api.nvim_create_augroup("powershell.nvim-filetype", { clear = true })

---@class powershell.autocmd
---@field id integer
---@field event string
---@field group? integer
---@field match string
---@field buf number
---@field file string
---@field data any

api.nvim_create_autocmd("Filetype", {
  group = group,
  pattern = "ps1",
  ---@param opts powershell.autocmd
  callback = function(opts) require("powershell").initialize_or_attach(opts.buf) end,
})
