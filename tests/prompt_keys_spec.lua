-- tests/prompt_keys_spec.lua
-- Telescope prompt input alaninda readline-benzeri duzenleme tuslari ve ilk
-- Esc'te kapatma.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/prompt_keys_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)
-- Testler normal modda kosar; insert imleci gibi satir sonunu (col == #line)
-- temsil edebilmek icin bir karakter ileri izin ver.
vim.opt.virtualedit = "onemore"

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

local function finish()
  io.write(string.format("\n%d/%d gecti, %d basarisiz\n", total - failures, total, failures))
  os.exit(failures == 0 and 0 or 1)
end

local ok, prompt_keys = pcall(require, "config.prompt_keys")
if not ok then
  io.write("FAIL - config.prompt_keys modulu yuklenemedi\n")
  failures = failures + 1
  finish()
end

local bufnr = vim.api.nvim_get_current_buf()
local function setup(line, col)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { line })
  vim.api.nvim_win_set_cursor(0, { 1, col })
end
local function line()
  return vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
end
local function col()
  return vim.api.nvim_win_get_cursor(0)[2]
end

-- ------------------------------------------------------------------ duzenleme
setup("basefoo bar", 11)
prompt_keys.delete_to_start()
check(line() == "" and col() == 0, "delete_to_start: satir basina kadar siler")

setup("basefoo bar", 11)
prompt_keys.delete_word()
check(line() == "basefoo" and col() == 7, "delete_word: onceki kelimeyi siler")

setup("basefoo bar", 7)
prompt_keys.delete_to_end()
check(line() == "basefoo" and col() == 7, "delete_to_end: satir sonuna kadar siler")

setup("basefoo", 3)
prompt_keys.move_end()
check(col() == 7, "move_end: satir sonuna gider")

setup("basefoo", 3)
prompt_keys.move_right()
check(col() == 4, "move_right: bir karakter sag")

setup("basefoo", 3)
prompt_keys.move_left()
check(col() == 2, "move_left: bir karakter sol")

setup("basefoo", 3)
prompt_keys.delete_forward()
check(line() == "basfoo" and col() == 3, "delete_forward: ileri karakter siler")

setup("basefoo", 0)
prompt_keys.move_left()
check(col() == 0, "move_left: satir basinda durur")

setup("basefoo", 7)
prompt_keys.move_right()
check(col() == 7, "move_right: satir sonunda durur")

-- ------------------------------------------------------------------ mappings
local mappings = prompt_keys.mappings()
for _, key in ipairs({ "<Esc>", "<C-u>", "<C-w>", "<C-k>", "<C-e>", "<C-b>", "<C-f>", "<C-d>" }) do
  check(type(mappings[key]) == "function", "mapping var: " .. key)
end

-- ----------------------------------------------------------------- telescope
local spec = dofile(root .. "/lua/plugins/telescope.lua")
local i = spec.opts and spec.opts.defaults and spec.opts.defaults.mappings and spec.opts.defaults.mappings.i
check(type(i) == "table", "telescope spec: insert mappings tanimli")
for _, key in ipairs({ "<Esc>", "<C-u>", "<C-w>", "<C-k>", "<C-e>" }) do
  check(i ~= nil and type(i[key]) == "function", "telescope insert mapping: " .. key)
end

finish()
