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
check(effective("n", "<C-l>").desc == "Sonraki kelime (<C-Right>)", "normal <C-l> bizim mapping")
check(effective("i", "<C-l>").desc == "Sonraki kelime (<C-Right>)", "insert <C-l> bizim mapping")

-- Ok tuslari korunur (regresyon): <C-Right> hala tanimli olmali.
check(effective("n", "<C-Right>").desc ~= "", "normal <C-Right> korunur")
check(effective("i", "<C-Right>").desc ~= "", "insert <C-Right> korunur")

-- Insert <C-h> = Ctrl+Backspace kelime silme KAYBOLMAMALI.
check(effective("i", "<C-H>").rhs == "<C-W>", "insert <C-h> hala <C-W> (kelime sil)")
check(effective("c", "<C-H>").rhs == "<C-W>", "cmdline <C-h> hala <C-W>")

-- <C-l> varsayilani kurtarildi mi?
check(vim.fn.maparg("<leader>r", "n") ~= "", "<leader>r redraw mapping var")

-- ------------------------------------------------------------- davranis testi
-- normal <C-h> onceki kelimenin basina, <C-l> sonraki kelimeye goturmeli.
do
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "bir iki uc" })
  vim.api.nvim_win_set_cursor(0, { 1, #"bir iki uc" - 1 }) -- son kelime icinde
  press("<C-h>")
  vim.wait(20)
  check(vim.api.nvim_win_get_cursor(0)[2] == #"bir iki ", "<C-h>: onceki kelime basi")

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  press("<C-l>")
  vim.wait(20)
  check(vim.api.nvim_win_get_cursor(0)[2] > 0, "<C-l>: sonraki kelimeye gider")
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
