-- tests/terminal_normal_mode_spec.lua
-- Terminal-normal mod: terminal modunda Esc normal moda gecer, normal modda
-- Esc calisan uygulamaya gonderilir; mapler yalnizca terminal buffer'inda.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/terminal_normal_mode_spec.lua

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

local term = require("config.terminal")
local text_win = vim.api.nvim_get_current_win()

-- cat -v, gelen ESC baytini gorunur "^[" olarak yansitir.
local shell_script = vim.fn.tempname()
vim.fn.writefile({ "#!/bin/sh", "exec cat -v" }, shell_script)
vim.fn.setfperm(shell_script, "rwxr-xr-x")
local old_shell = vim.o.shell
vim.o.shell = shell_script

term.toggle()
local term_buf = vim.api.nvim_get_current_buf()
vim.wait(300)

check(vim.bo[term_buf].buftype == "terminal", "terminal buffer acildi")

-- Terminal modunda Esc normal moda gecmeli.
local t_esc = vim.fn.maparg("<Esc>", "t", false, true)
check(t_esc.rhs == "<C-\\><C-n>", "t modu Esc terminal-normal moda gecer")

-- Normal modda Esc, calisan uygulamaya ESC bayti gondermeli.
local n_esc = vim.fn.maparg("<Esc>", "n", false, true)
check(n_esc.desc == "Esc'i terminal uygulamasina gonder", "n modu Esc calisan uygulamaya gonderir")

if n_esc.callback then
  n_esc.callback()
end
vim.fn.chansend(vim.b[term_buf].terminal_job_id, "X\n")
local escaped = vim.wait(2000, function()
  local text = table.concat(vim.api.nvim_buf_get_lines(term_buf, 0, -1, false), "\n")
  return text:find("%^%[") ~= nil
end)
check(escaped, "n modu Esc uygulamaya ulasti")

-- Mapler terminal buffer'ina ozel olmali; metin penceresine sizmamali.
term.toggle()
check(vim.api.nvim_get_current_win() == text_win, "terminal kapandi, odak metinde")
check(vim.fn.maparg("<Esc>", "n", false, true).desc == nil, "n modu Esc metin buffer'inda tanimsiz")
check(vim.tbl_isempty(vim.fn.maparg("<Esc>", "t", false, true)), "t modu Esc metin buffer'inda tanimsiz")

vim.o.shell = old_shell
vim.fn.delete(shell_script)

io.write(string.format("\n%d/%d gecti, %d basarisiz\n", total - failures, total, failures))
os.exit(failures == 0 and 0 or 1)
