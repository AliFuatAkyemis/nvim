-- tests/terminal_toggle_spec.lua
-- <C-j> terminal toggle: alt split, startup cwd, tek buffer, odak donusu.
-- Split her zaman metin penceresinin altina acilir (neo-tree odaktayken dahil).
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/terminal_toggle_spec.lua

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

local startup_cwd = vim.uv.cwd()
local term = require("config.terminal")

local text_win = vim.api.nvim_get_current_win()

-- Modul yuklendikten sonra cwd degisse bile terminal startup dizininde acilmali.
vim.cmd("cd /tmp")

-- ------------------------------------------------------------------- acilis
term.toggle()

local wins = vim.api.nvim_tabpage_list_wins(0)
local term_win = vim.api.nvim_get_current_win()
local term_buf = vim.api.nvim_get_current_buf()

check(#wins == 2, "acilis: iki pencere var")
check(term_win ~= text_win, "acilis: terminal ayri pencerede")
check(vim.bo[term_buf].buftype == "terminal", "acilis: buffer buftype terminal")
check(vim.api.nvim_win_get_position(term_win)[1] > vim.api.nvim_win_get_position(text_win)[1], "acilis: terminal metin penceresinin altinda")
check(vim.api.nvim_get_current_win() == term_win, "acilis: odak terminalde")

local job = vim.b[term_buf].terminal_job_id
local pid = job and vim.fn.jobpid(job) or 0
local term_cwd = pid > 0 and vim.uv.fs_readlink("/proc/" .. pid .. "/cwd") or nil
check(term_cwd == startup_cwd, "acilis: terminal startup dizininde")

-- ----------------------------------------------------------------- kapanis
term.toggle()

check(#vim.api.nvim_tabpage_list_wins(0) == 1, "kapanis: terminal penceresi gitti")
check(vim.api.nvim_buf_is_valid(term_buf), "kapanis: terminal buffer canli")
check(vim.api.nvim_get_current_win() == text_win, "kapanis: odak metin penceresine dondu")

-- --------------------------------------------------------------- yeniden ac
term.toggle()

check(#vim.api.nvim_tabpage_list_wins(0) == 2, "yeniden: alt split geri geldi")
check(vim.api.nvim_get_current_buf() == term_buf, "yeniden: ayni terminal buffer'i")
check(vim.api.nvim_get_current_win() ~= text_win, "yeniden: odak terminalde")

term.toggle()

-- ------------------------------- odak terminalde degilken kapatmaz, odaklar
term.toggle()
vim.api.nvim_set_current_win(text_win)
term.toggle()

check(#vim.api.nvim_tabpage_list_wins(0) == 2, "odak: terminal acik kalir")
check(vim.api.nvim_get_current_win() ~= text_win, "odak: terminale gider")
check(vim.api.nvim_get_current_buf() == term_buf, "odak: terminal buffer'indasin")

term.toggle()
check(#vim.api.nvim_tabpage_list_wins(0) == 1, "odak: terminaldeyken kapanir")
check(vim.api.nvim_get_current_win() == text_win, "odak: metne geri doner")

-- ----------------------------------------------------------- shell cikisi
term.toggle()
local exit_buf = vim.api.nvim_get_current_buf()
vim.fn.chansend(vim.b[exit_buf].terminal_job_id, "exit\n")

local cleaned = vim.wait(3000, function()
  return not vim.api.nvim_buf_is_valid(exit_buf)
    and #vim.api.nvim_tabpage_list_wins(0) == 1
    and vim.api.nvim_get_current_win() == text_win
end)

check(cleaned, "cikis: shell exit sonrasi pencere kapandi, odak metinde")
term.toggle()
check(vim.api.nvim_get_current_buf() ~= exit_buf, "cikis: sonraki acilis yeni terminal buffer'i")
check(vim.bo.buftype == "terminal", "cikis: yeni buffer terminal")
term.toggle()

-- --------------------------------------- metin penceresi odakta degilken
-- Neo-tree benzeri yan pencere odaktayken split yine metin penceresinin altina
-- acilmali, yan pencerenin altina degil.
vim.cmd("topleft vsplit")
local neo_win = vim.api.nvim_get_current_win()
local neo_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(neo_win, neo_buf)
vim.bo[neo_buf].filetype = "neo-tree"
vim.api.nvim_set_current_win(neo_win)
vim.wait(20)

term.toggle()
local side_term_win = vim.api.nvim_get_current_win()
local term_pos = vim.api.nvim_win_get_position(side_term_win)
local text_pos = vim.api.nvim_win_get_position(text_win)

check(term_pos[2] == text_pos[2], "yan pencere: terminal metin sutununda")
check(term_pos[1] > text_pos[1], "yan pencere: terminal metin penceresinin altinda")
check(vim.api.nvim_get_current_win() == side_term_win, "yan pencere: odak terminalde")

-- Terminal acikken odak yan penceredeyse kapatmaz, terminale tasir.
vim.api.nvim_set_current_win(neo_win)
term.toggle()
check(vim.api.nvim_get_current_win() == side_term_win, "yan pencere: odak terminale gider")
check(#vim.api.nvim_tabpage_list_wins(0) == 3, "yan pencere: terminal acik kalir")

-- Terminaldeyken kapatma, terminale gelinen yan pencereye doner.
term.toggle()
check(#vim.api.nvim_tabpage_list_wins(0) == 2, "yan pencere: terminaldeyken kapanir")
check(vim.api.nvim_get_current_win() == neo_win, "yan pencere: cikista neo-tree'ye doner")
pcall(vim.api.nvim_win_close, neo_win, true)

-- Opencode penceresinden gelindiyse kapatma oraya doner.
vim.cmd("vsplit")
local opencode_win = vim.api.nvim_get_current_win()
local opencode_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(opencode_win, opencode_buf)
vim.bo[opencode_buf].filetype = "opencode"
vim.api.nvim_set_current_win(opencode_win)
vim.wait(20)

term.toggle()
check(vim.bo.buftype == "terminal", "opencode: terminal acildi")
check(vim.api.nvim_get_current_win() ~= opencode_win, "opencode: odak terminalde")
term.toggle()
check(vim.api.nvim_get_current_win() == opencode_win, "opencode: cikista opencode'a doner")
pcall(vim.api.nvim_win_close, opencode_win, true)

-- ------------------------------------------ metin penceresi hic yokken
vim.cmd("tabnew")
vim.cmd("enew")
vim.bo.buftype = "nofile"
vim.bo.filetype = "neo-tree"
local only_win = vim.api.nvim_get_current_win()

term.toggle()
local fallback_term_win = vim.api.nvim_get_current_win()
check(vim.api.nvim_win_get_position(fallback_term_win)[1] > vim.api.nvim_win_get_position(only_win)[1], "metinsiz: mevcut pencerenin altinda")
term.toggle()
check(vim.api.nvim_get_current_win() == only_win, "metinsiz: kapaninca mevcut pencereye dondu")
vim.cmd("tabclose")

-- ------------------------------------------------------------------ keymap
package.preload["telescope.builtin"] = function()
  return { find_files = function() end, live_grep = function() end }
end
dofile(root .. "/lua/config/keymaps.lua")

local leader_j = vim.api.nvim_replace_termcodes("<leader>j", true, false, true)

local function mapped(mode)
  return vim.fn.maparg("<C-j>", mode, false, true)
end

for _, mode in ipairs({ "n", "i", "v", "s", "t" }) do
  check(mapped(mode).desc == "Terminal aç/kapat", "<C-j> " .. mode .. " modunda terminal toggle")
end
check(vim.fn.maparg(leader_j, "n", false, true).desc == nil, "<leader>j terminal degil")

-- Layout manager acikken terminal, altina acildigi metin penceresiyle ayni
-- genislikte kalmali (dikey split varken de).
vim.cmd("vsplit")
vim.api.nvim_set_current_win(text_win)
vim.wait(100)
term.toggle()
vim.wait(150)
local layout_term_win = vim.api.nvim_get_current_win()
check(vim.api.nvim_win_get_width(layout_term_win) == vim.api.nvim_win_get_width(text_win), "layout: terminal metin penceresiyle ayni genislikte")
term.toggle()

-- Neo-tree genisligi terminal acilip kapanirken degismemeli.
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if win ~= text_win then
    pcall(vim.api.nvim_win_close, win, true)
  end
end
vim.wait(200)
vim.cmd("topleft vsplit")
local stable_neo_win = vim.api.nvim_get_current_win()
local stable_neo_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(stable_neo_win, stable_neo_buf)
vim.bo[stable_neo_buf].filetype = "neo-tree"
vim.api.nvim_set_current_win(text_win)
vim.wait(300)

local neo_width_before = vim.api.nvim_win_get_width(stable_neo_win)
term.toggle()
vim.wait(300)
check(vim.api.nvim_win_get_width(stable_neo_win) == neo_width_before, "neo: terminal acilinca genislik degismez")
term.toggle()
vim.wait(300)
check(vim.api.nvim_win_get_width(stable_neo_win) == neo_width_before, "neo: terminal kapaninca genislik degismez")
pcall(vim.api.nvim_win_close, stable_neo_win, true)

-- -------------------------------------- oranli yükseklik (pencere boyutu)
-- Terminal yüksekliği sabit satır değil, pencere yüksekliğine oranlı olmalı:
-- tam ekranda ~%28, pencere küçüldükçe doğrusal olarak %50'ye çıkar.
-- Gerçek UI resize'ında VimResized otomatik tetiklenir; headless'ta elle
-- tetikliyoruz (bkz. pty ile doğrulanan tam ekran davranışı).
local function term_height()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "terminal" then
      return vim.api.nvim_win_get_height(win)
    end
  end
end

local function resize_window(lines)
  vim.o.lines = lines
  vim.cmd("doautocmd VimResized")
  vim.wait(100)
end

term.toggle()
vim.wait(150)

resize_window(24)
local h_small = term_height()
check(h_small == 12, "yükseklik: 24 satırda 12 satır (~%50)")

resize_window(60)
local h_full = term_height()
check(h_full == term.target_height(), "yükseklik: 60 satırda hedef yükseklik")
check(h_full == 16, "yükseklik: 60 satırda 16 satır (~%28)")
check(h_full <= math.floor(60 * 0.30), "yükseklik: 60 satırda ekranın %30'unu geçmez")
check(h_full > h_small, "yükseklik: büyük pencerede mutlak yükseklik artar")

resize_window(40)
local h_mid = term_height()
check(h_mid == term.target_height(), "yükseklik: 40 satırda hedef yükseklik")
check(h_mid == 14, "yükseklik: 40 satırda 14 satır (doğrusal ara değer)")
check(h_mid > h_small and h_mid < h_full, "yükseklik: ara boyutta ara yükseklik")

resize_window(60)
check(term_height() == 16, "yükseklik: tekrar büyüyünce güncellenir")

resize_window(24)
check(term_height() == 12, "yükseklik: tekrar küçülünce %50'ye döner")
term.toggle()

io.write(string.format("\n%d/%d gecti, %d basarisiz\n", total - failures, total, failures))
os.exit(failures == 0 and 0 or 1)
