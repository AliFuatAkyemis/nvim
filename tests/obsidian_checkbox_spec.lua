-- tests/obsidian_checkbox_spec.lua
-- Normal-mod <CR> (obsidian smart_action) liste maddelerini checkbox'a
-- CEVIRMEMELI; yalnizca zaten checkbox olan maddeleri isaretleyip kaldirmali.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/obsidian_checkbox_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(vim.fn.expand("~/.local/share/nvim/lazy/obsidian.nvim"))

local failures, total = 0, 0
local function check(cond, label)
  total = total + 1
  if cond then
    io.write("ok   - " .. label .. "\n")
  else
    failures = failures + 1
    io.write("FAIL - " .. label .. "\n")
  end
end

local spec = dofile(root .. "/lua/plugins/obsidian.lua")
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local opts = vim.tbl_deep_extend("force", spec.opts, { workspaces = { { name = "t", path = tmp } } })
require("obsidian").setup(opts)
local actions = require("obsidian.actions")

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = "markdown"

local function act(line, col)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
  vim.api.nvim_win_set_cursor(0, { 1, col })
  return actions.smart_action() or ""
end

check(act("2. b", 3) == "<CR>", "sirali maddeyi checkbox yapmaz")
check(act("- madde", 2) == "<CR>", "bullet maddeyi checkbox yapmaz")
check(act("- [ ] x", 5):match("toggle_checkbox") ~= nil, "mevcut bos checkbox'i cevirir")
check(act("- [x] x", 5):match("toggle_checkbox") ~= nil, "mevcut isaretli checkbox'i cevirir")

vim.fn.delete(tmp, "rf")
io.write(string.format("\n%d/%d gecti, %d basarisiz\n", total - failures, total, failures))
os.exit(failures == 0 and 0 or 1)
