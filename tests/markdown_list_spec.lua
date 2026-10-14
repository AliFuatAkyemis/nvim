-- tests/markdown_list_spec.lua
-- config/markdown.lua icindeki liste duzenleme fonksiyonlari icin headless test.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/markdown_list_spec.lua
--
-- Basarisizlikta sifir olmayan cikis kodu doner.

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local M = require("config.markdown")

local failures = 0
local total = 0

local function check(actual, expected, label)
  total = total + 1
  if vim.deep_equal(actual, expected) then
    io.write("ok   - " .. label .. "\n")
  else
    failures = failures + 1
    io.write("FAIL - " .. label .. "\n")
    io.write("       expected: " .. vim.inspect(expected) .. "\n")
    io.write("       actual:   " .. vim.inspect(actual) .. "\n")
  end
end

-- Verilen satirlar/imlec ile temiz bir buffer ac, fn() cagir,
-- sonucu (handled, satirlar, imlec) olarak dondur.
local function run(lines, row, col, fn)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  -- Gerçek kullanım insert moddadır; `startinsert` olmadan nvim_win_set_cursor
  -- normal modda col == #line konumunu kırpar. Fonksiyonlar insert-noktası
  -- semantiği kullandığı için testte de bu moda geçilir.
  vim.cmd("startinsert")
  vim.api.nvim_win_set_cursor(0, { row, col })
  local handled = fn()
  local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local cur = vim.api.nvim_win_get_cursor(0)
  vim.api.nvim_buf_delete(buf, { force = true })
  return handled, out, cur
end

--------------------------------------------------------------------------
-- new_list_item: Enter -> sonraki madde
--------------------------------------------------------------------------

do
  local h, out, cur = run({ "1. birinci madde" }, 1, 16, M.new_list_item)
  check({ h, out, cur }, { true, { "1. birinci madde", "2. " }, { 2, 3 } }, "ordered: sonraki madde +1")
end

do
  local h, out, cur = run({ "   3. ucuncu" }, 1, 12, M.new_list_item)
  check({ h, out, cur }, { true, { "   3. ucuncu", "   4. " }, { 2, 6 } }, "ordered: ic ice girinti korunur")
end

do
  local h, out, cur = run({ "1) madde" }, 1, 8, M.new_list_item)
  check({ h, out, cur }, { true, { "1) madde", "2) " }, { 2, 3 } }, "ordered: ')' ayraci korunur")
end

do
  local h, out, cur = run({ "- madde" }, 1, 7, M.new_list_item)
  check({ h, out, cur }, { true, { "- madde", "- " }, { 2, 2 } }, "bullet: '-' imi devam eder")
end

do
  local h, out, cur = run({ "* madde" }, 1, 7, M.new_list_item)
  check({ h, out, cur }, { true, { "* madde", "* " }, { 2, 2 } }, "bullet: '*' imi devam eder")
end

do
  local h, out, cur = run({ "- [x] is" }, 1, 8, M.new_list_item)
  check({ h, out, cur }, { true, { "- [x] is", "- [ ] " }, { 2, 6 } }, "checkbox: yeni madde isaretsiz")
end

do
  local h, out, cur = run({ "2. " }, 1, 3, M.new_list_item)
  check({ h, out, cur }, { true, { "" }, { 1, 0 } }, "bos ordered madde: isaret kaldirilir")
end

do
  local h, out, cur = run({ "   - " }, 1, 5, M.new_list_item)
  check({ h, out, cur }, { true, { "   " }, { 1, 3 } }, "bos bullet: isaret kaldirilir, girinti kalir")
end

do
  local h, out, cur = run({ "1. madde" }, 1, 3, M.new_list_item)
  check({ h, out, cur }, { false, { "1. madde" }, { 1, 3 } }, "satir ortasi: islenmez")
end

do
  local h, out, cur = run({ "merhaba" }, 1, 7, M.new_list_item)
  check({ h, out, cur }, { false, { "merhaba" }, { 1, 7 } }, "liste degil: islenmez")
end

do
  local h, out, cur = run({ "```", "- kod" }, 2, 5, M.new_list_item)
  check({ h, out, cur }, { false, { "```", "- kod" }, { 2, 5 } }, "kod blogu icinde: islenmez")
end

do
  local h, out, cur = run({ "```", "x", "```", "- gercek" }, 4, 8, M.new_list_item)
  check({ h, out, cur }, { true, { "```", "x", "```", "- gercek", "- " }, { 5, 2 } }, "kod blogundan sonra: islenir")
end

--------------------------------------------------------------------------
-- soft_break: Shift+Enter -> ayni maddeye metin hizasinda devam
--------------------------------------------------------------------------

do
  local h, out, cur = run({ "1. birinci madde" }, 1, 16, M.soft_break)
  check({ h, out, cur }, { true, { "1. birinci madde", "   " }, { 2, 3 } }, "soft: icerik sutununa girintilenir")
end

do
  local h, out, cur = run({ "1. birinci madde" }, 1, 3, M.soft_break)
  check({ h, out, cur }, { true, { "1. ", "   birinci madde" }, { 2, 3 } }, "soft: satir ici bolunur")
end

do
  local h, out, cur = run({ "- madde" }, 1, 7, M.soft_break)
  check({ h, out, cur }, { true, { "- madde", "  " }, { 2, 2 } }, "soft: bullet girintisi")
end

do
  local h, out, cur = run({ "- [ ] is" }, 1, 8, M.soft_break)
  check({ h, out, cur }, { true, { "- [ ] is", "      " }, { 2, 6 } }, "soft: checkbox girintisi")
end

do
  local h, out, cur = run({ "   3. madde" }, 1, 11, M.soft_break)
  check({ h, out, cur }, { true, { "   3. madde", "      " }, { 2, 6 } }, "soft: ic ice girinti")
end

do
  local h, out, cur = run({ "1. birinci madde", "   " }, 2, 3, M.soft_break)
  check({ h, out, cur }, { true, { "1. birinci madde", "" }, { 2, 0 } }, "soft: bos devam satiri girintisi kaldirilir")
end

do
  local h, out, cur = run({ "1. birinci madde", "   devam" }, 2, 8, M.soft_break)
  check(
    { h, out, cur },
    { true, { "1. birinci madde", "   devam", "   " }, { 3, 3 } },
    "soft: devam satirindan tekrar devam"
  )
end

do
  local h, out, cur = run({ "merhaba" }, 1, 7, M.soft_break)
  check({ h, out, cur }, { false, { "merhaba" }, { 1, 7 } }, "soft: liste baglami yok")
end

do
  local h, out, cur = run({ "```", "1. kod" }, 2, 6, M.soft_break)
  check({ h, out, cur }, { false, { "```", "1. kod" }, { 2, 6 } }, "soft: kod blogu icinde islenmez")
end

--------------------------------------------------------------------------

io.write(string.format("\n%d/%d gecti, %d basarisiz\n", total - failures, total, failures))
os.exit(failures == 0 and 0 or 1)
