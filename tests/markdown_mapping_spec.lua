-- tests/markdown_mapping_spec.lua
-- ftplugin/markdown.lua mapping davranislari icin headless entegrasyon testi.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/markdown_mapping_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.cmd("filetype plugin on")

-- ftplugin'in kuruldugu gecici markdown buffer
local tmp = vim.fn.tempname() .. ".md"
vim.fn.writefile({ "" }, tmp)
vim.cmd("edit " .. vim.fn.fnameescape(tmp))

local function callback(mode, lhs)
  for _, km in ipairs(vim.api.nvim_buf_get_keymap(0, mode)) do
    if km.lhs == lhs then
      return km.callback
    end
  end
  return nil
end

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

local o = callback("n", "o")
local cr = callback("i", "<CR>")

check(o ~= nil, "o mapping kurulu")
check(callback("n", "O") == nil, "O varsayilan kalir")

-- o: liste maddesinde sonraki madde acilir ve imlec satir sonuna (boslugun
-- sagina) gelir; aksi halde "6. |" kalip Enter bosluğu goremedigi icin
-- isareti kaldiramaz.
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "5. besinci" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
o()
vim.wait(10)
do
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local cur = vim.api.nvim_win_get_cursor(0)
  check(vim.deep_equal(lines, { "5. besinci", "6. " }), "o: sonraki madde acilir")
  check(cur[2] == #lines[2], "o: imlec satir sonunda (bosluk solda kalir)")
end

-- o sonrasi bos madde: Enter (insert <CR>) madde isaretini kaldirmali
do
  cr() -- imlec zaten satir sonunda
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  check(lines[2] == "", "o sonrasi bos madde: Enter isareti kaldirir")
end

-- silme sonrasi yeniden numaralama (nvim_buf_attach on_lines otomatik tetikler)
local function del(cmd, init)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, init)
  vim.cmd(cmd)
  vim.wait(30)
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

check(
  vim.deep_equal(del("normal! 3Gdd", { "1. a", "2. b", "3. c", "4. d" }), { "1. a", "2. b", "3. d" }),
  "silme: orta madde -> sonrasi kapanir"
)
check(
  vim.deep_equal(del("normal! 2Gdd", { "1. a", "2. b", "", "3. c", "4. d" }), { "1. a", "", "3. c", "4. d" }),
  "silme: bos satir blogu boler"
)
check(
  vim.deep_equal(
    del("normal! 3Gdd", { "1. a", "2. b", "3. c", "```", "7. x", "7. y", "```" }),
    { "1. a", "2. b", "```", "7. x", "7. y", "```" }
  ),
  "silme: kod blogu korunur"
)

-- Bir maddenin numarasi duzenlenip insert'tan cikilinca liste guncellenmeli
-- (on_lines geri cagrisi beklenmeden; InsertLeave senkron tetiklenir).
do
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "1. a", "5. b", "9. c" })
  vim.api.nvim_exec_autocmds("InsertLeave", { buffer = 0 })
  local out = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  check(vim.deep_equal(out, { "1. a", "2. b", "3. c" }), "InsertLeave: liste guncellenir")
end

vim.fn.delete(tmp)
io.write(string.format("\n%d/%d gecti, %d basarisiz\n", total - failures, total, failures))
os.exit(failures == 0 and 0 or 1)
