-- tests/layout_column_spec.lua
-- Layout manager: yatay split'teki pencereler ayni kolonu paylasir. Terminal
-- acikken odak degisimi Neo-tree genisligini degistirmemeli. Farkli dikey
-- kolonlar (metin + opencode) varken odak genisligi kurali calismaya devam eder.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/layout_column_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)

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

package.preload["telescope.builtin"] = function()
  return { find_files = function() end, live_grep = function() end }
end

local term = require("config.terminal")
dofile(root .. "/lua/config/keymaps.lua")

local function find(pred)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if pred(win) then
      return win
    end
  end
  return nil
end

local function neo_win()
  return find(function(win)
    return vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neo-tree"
  end)
end

local function text_win()
  return find(function(win)
    local buf = vim.api.nvim_win_get_buf(win)
    return vim.bo[buf].buftype == "" and vim.bo[buf].filetype == "lua"
  end)
end

local function term_win()
  return find(function(win)
    return vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "terminal"
  end)
end

local function width(win)
  return win and vim.api.nvim_win_get_width(win) or -1
end

local function layout_ok(label)
  local neo = neo_win()
  local text = text_win()
  local terminal = term_win()
  check(width(neo) == 30, label .. ": Neo-tree genisligi 30")
  check(width(text) == width(terminal), label .. ": metin ve terminal ayni genislikte")
end

vim.cmd("enew")
vim.bo.filetype = "lua"
local text = vim.api.nvim_get_current_win()

vim.cmd("topleft vsplit")
local neo = vim.api.nvim_get_current_win()
local neo_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(neo, neo_buf)
vim.bo[neo_buf].filetype = "neo-tree"
vim.wo[neo].winfixwidth = true
vim.api.nvim_win_set_width(neo, 30)
vim.api.nvim_set_current_win(text)
vim.wait(300)

term.toggle()
vim.wait(600)
layout_ok("terminal acildi")

vim.api.nvim_set_current_win(text)
vim.wait(300)
layout_ok("metne odaklanildi")

local tw = term_win()
vim.api.nvim_set_current_win(tw)
vim.wait(300)
layout_ok("terminale odaklanildi")

vim.api.nvim_set_current_win(neo_win())
vim.wait(300)
layout_ok("Neo-tree'ye odaklanildi")

vim.api.nvim_set_current_win(text_win())
vim.wait(300)
layout_ok("metne tekrar odaklanildi")

-- Farkli dikey kolonlar varken oran kurali calismali: neo-tree disinda
-- metin ve opencode kolonlari varsa odaktaki metin %70 genislige gelir.
vim.api.nvim_set_current_win(term_win())
term.toggle()
vim.wait(500)
vim.api.nvim_set_current_win(text_win())
vim.wait(300)

vim.cmd("vsplit")
local opencode = vim.api.nvim_get_current_win()
local opencode_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(opencode, opencode_buf)
vim.bo[opencode_buf].filetype = "opencode"
vim.api.nvim_set_current_win(text_win())
vim.wait(400)

check(width(neo_win()) == 30, "opencode kolonu: Neo-tree genisligi 30")
check(width(text_win()) == 35, "opencode kolonu: metin %70 genislikte")

io.write(string.format("\n%d/%d gecti, %d basarisiz\n", total - failures, total, failures))
os.exit(failures == 0 and 0 or 1)
