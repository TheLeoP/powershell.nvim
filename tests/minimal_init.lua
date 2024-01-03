---@param name string
local function bootstrap(name)
  local dir = ("/tmp/" .. name)
  local is_not_a_directory = vim.fn.isdirectory(dir) == 0
  if is_not_a_directory then vim.fn.system { "git", "clone", "https://github.com/" .. name, dir } end
  vim.opt.rtp:append(dir)
end

vim.opt.rtp:append "."
bootstrap "nvim-lua/plenary.nvim"
bootstrap "williamboman/mason.nvim"

vim.cmd "runtime plugin/plenary.vim"
-- require "plenary.busted"

local Package = require "mason-core.package"
local registry = require "mason-registry"

require("mason-registry").refresh()
local package_name, version = Package.Parse "powershell-editor-services"
local pkg = registry.get_package(package_name)
return pkg:install {
  version = version,
}
