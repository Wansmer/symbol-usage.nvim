local root = vim.fn.fnamemodify('./.tests', ':p')

vim.opt.writebackup = false
vim.opt.swapfile = false
vim.opt.shadafile = 'NONE'
vim.opt.packpath = { root .. '/site' }
vim.opt.runtimepath:append(root)

for _, name in ipairs({ 'config', 'data', 'state', 'cache' }) do
  vim.env[('XDG_%s_HOME'):format(name:upper())] = vim.fs.joinpath(root, name)
end

if vim.fn.executable('lua-language-server') ~= 1 then
  error('lua-language-server is not executable', vim.log.levels.ERROR)
end

local function install_dep(plugin)
  local name = plugin:match('.*/(.*)')
  local package_root = vim.fs.joinpath(root, '/site/pack/deps/start/')
  if not vim.uv.fs_stat(vim.fs.joinpath(package_root, name)) then
    vim.fn.mkdir(package_root, 'p')
    vim.fn.system({
      'git',
      'clone',
      '--filter=blob:none',
      'https://github.com/' .. plugin .. '.git',
      vim.fs.joinpath(package_root, name),
    })
  end
end

local dependencies = {
  'nvim-lua/plenary.nvim',
  'neovim/nvim-lspconfig',
}

for _, plugin in ipairs(dependencies) do
  install_dep(plugin)
end

require('plenary.busted')
require('lspconfig').lua_ls.setup({})
