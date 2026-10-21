-- tests/keymap_word_nav_spec.lua
-- <C-h>/<C-l> kelime atlama alias'lari ve markdown Vurgu tasima testi.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/keymap_word_nav_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)

vim.g.mapleader = " "

-- keymaps.lua en ustte telescope.builtin'e bagimli; headless testte sahte modul.
package.preload["telescope.builtin"] = function()
  return { find_files = function() end, live_grep = function() end }
end
dofile(root .. "/lua/config/keymaps.lua")

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

local function find_km(list, lhs)
  -- lhs normalizasyonu: <C-h> -> <C-H> olabilir; buyuk/kucuk harf duyarsiz.
  local want = lhs:lower()
  for _, m in ipairs(list) do
    if m.lhs:lower() == want then
      return m
    end
  end
  return nil
end

local function buf_km(mode, lhs)
  return find_km(vim.api.nvim_buf_get_keymap(0, mode), lhs)
end

-- Etkin (effective) mapping: nvim_get_keymap listesinde Neovim'in dahili
-- varsayilanlari da bulunabilir (orn. normal <C-L> redraw). Bu yuzden
-- maparg ile cozulen mapping'in bizim desc'imizi tasidigina bakilir.
local function effective(mode, lhs)
  return vim.fn.maparg(lhs, mode, false, true)
end

local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

-- --------------------------------------------------------------- kelime atlama
check(effective("n", "<C-h>").desc == "Önceki kelime (<C-Left>)", "normal <C-h> bizim mapping")
check(effective("i", "<C-h>").desc == "Önceki kelime (<C-Left>)", "insert <C-h> bizim mapping")
check(effective("n", "<C-l>").desc == "Sonraki kelime (<C-Right>)", "normal <C-l> bizim mapping")
check(effective("i", "<C-l>").desc == "Sonraki kelime (<C-Right>)", "insert <C-l> bizim mapping")
check(effective("x", "<C-h>").desc == "Önceki kelime (<C-Left>)", "visual <C-h> bizim mapping")
check(effective("x", "<C-l>").desc == "Sonraki kelime (<C-Right>)", "visual <C-l> bizim mapping")

-- Ok tuslari korunur (regresyon): <C-Right> hala tanimli olmali.
check(effective("n", "<C-Right>").desc ~= "", "normal <C-Right> korunur")
check(effective("i", "<C-Right>").desc ~= "", "insert <C-Right> korunur")

-- Insert <C-h> artik silmez; kelime silme <C-BS> ve cmdline <C-H>'ta kalir.
check(effective("i", "<C-BS>").rhs == "<C-W>", "insert <C-BS> hala <C-W> (Ctrl+Backspace)")
check(effective("c", "<C-BS>").rhs == "<C-W>", "cmdline <C-BS> hala <C-W>")
check(effective("c", "<C-H>").rhs == "<C-W>", "cmdline <C-h> hala <C-W>")

-- Insert <C-a> satir basina gider (Neo-tree create/rename/move girdileri insert
-- modda acilir; yerlesik i_CTRL-A metin ekler, imleci tasimaz).
check(effective("i", "<C-a>").rhs == "<Home>", "insert <C-a> hala <Home>")
do
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "  hello" })
  vim.api.nvim_win_set_cursor(0, { 1, 7 })
  press("i<C-a>")
  vim.wait(30)
  check(vim.api.nvim_win_get_cursor(0)[2] == 0, "insert <C-a> imleci satir basina tasir")
  check(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "  hello", "insert <C-a> metin eklemez")
  press("<Esc>")
  vim.wait(10)
end

-- <C-l> varsayilani kurtarildi mi?
check(vim.fn.maparg("<leader>r", "n") ~= "", "<leader>r redraw mapping var")

-- --------------------------------------------------- ok tusuyla denklik testi
-- Asil gereksinim: <C-h>/<C-l>, <C-Left>/<C-Right> ile ayni yere gitmeli.
local LINES = { "bir iki uc", "dort bes alti" }

-- keys: feed edilecek dizi; start: {row, col} (1-indexed)
local function pos_after(keys, start)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, LINES)
  vim.api.nvim_win_set_cursor(0, start)
  press(keys)
  vim.wait(30)
  local p = vim.api.nvim_win_get_cursor(0)
  local anchor = vim.fn.getpos("v")[3]
  local line = vim.api.nvim_buf_get_lines(0, 0, -1, false)[1]
  press("<Esc>")
  vim.wait(10)
  return { p[1], p[2], anchor, line }
end

local function same(keys_a, keys_b, start, label)
  local a = pos_after(keys_a, start)
  local b = pos_after(keys_b, start)
  check(vim.deep_equal(a, b), label .. " (imlec+anchor+metin ayni)")
end

-- normal
same("<C-h>", "<C-Left>", { 1, 6 }, "normal: <C-h> == <C-Left>")
same("<C-l>", "<C-Right>", { 1, 0 }, "normal: <C-l> == <C-Right>")

-- insert (X yazarak insert moda gec)
same("iX<C-h>", "iX<C-Left>", { 1, 6 }, "insert: <C-h> == <C-Left>")
same("iX<C-l>", "iX<C-Right>", { 1, 0 }, "insert: <C-l> == <C-Right>")

-- visual / visual-line / visual-block
same("v<C-h>", "v<C-Left>", { 1, 6 }, "visual: <C-h> == <C-Left>")
same("v<C-l>", "v<C-Right>", { 1, 0 }, "visual: <C-l> == <C-Right>")
same("V<C-h>", "V<C-Left>", { 2, 5 }, "V-line: <C-h> == <C-Left>")
same("V<C-l>", "V<C-Right>", { 1, 0 }, "V-line: <C-l> == <C-Right>")
same("\22<C-h>", "\22<C-Left>", { 2, 5 }, "block: <C-h> == <C-Left>")
same("\22<C-l>", "\22<C-Right>", { 1, 0 }, "block: <C-l> == <C-Right>")

-- Insert <C-h> metni degistirmemeli (eski davranis: kelime siliyordu).
do
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "bir iki uc" })
  vim.api.nvim_win_set_cursor(0, { 1, 3 })
  press("iX<C-h>")
  vim.wait(30)
  check(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "birX iki uc", "insert <C-h> metni silmez")
  press("<Esc>")
  vim.wait(10)
end

-- ----------------------------------------------------------------- markdown
vim.cmd("filetype plugin on")
local tmp = vim.fn.tempname() .. ".md"
vim.fn.writefile({ "" }, tmp)
vim.cmd("edit " .. vim.fn.fnameescape(tmp))

-- buffer-local mapping'lerde <leader> genisletilmis halde gorunur (leader = space).
local leader_lh = vim.api.nvim_replace_termcodes("<leader>lh", true, false, true)

check(buf_km("n", "<C-l>") == nil, "markdown: <C-l> artik buffer-local degil")
check(buf_km("i", "<C-l>") == nil, "markdown insert: <C-l> buffer-local degil")
check(buf_km("n", leader_lh) ~= nil, "markdown: <leader>lh Vurgu kurulu")
check(buf_km("i", leader_lh) ~= nil, "markdown insert: <leader>lh Vurgu kurulu")
-- Vurgu davranisi hala calisiyor mu?
do
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd("startinsert")
  buf_km("i", leader_lh).callback()
  local line = vim.api.nvim_buf_get_lines(0, 0, -1, false)[1]
  check(line:find("==") ~= nil, "markdown: <leader>lh vurgu isaretini acar")
end

vim.fn.delete(tmp)
io.write(string.format("\n%d/%d gecti, %d basarisiz\n", total - failures, total, failures))
os.exit(failures == 0 and 0 or 1)
