-- tests/empty_buffer_spec.lua
-- [No Name] sekmesi sadece acik dosya yokken kalmali; bir dosya acilinca
-- bos, degismemis ve gorunmeyen anonim buffer'lar silinmeli.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/empty_buffer_spec.lua

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

local ok, empty = pcall(require, "config.empty_buffer")
check(ok, "config.empty_buffer modulu yuklenir")
if not ok then
  io.write("FAIL - " .. tostring(empty) .. "\n")
  os.exit(1)
end

empty.setup()

local function is_empty_listed(buf)
  return vim.api.nvim_buf_is_valid(buf)
    and vim.bo[buf].buflisted
    and vim.bo[buf].buftype == ""
    and vim.api.nvim_buf_get_name(buf) == ""
end

local function count_empty_listed()
  local n = 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if is_empty_listed(buf) then
      n = n + 1
    end
  end
  return n
end

local function open_file()
  local path = vim.fn.tempname() .. ".lua"
  vim.fn.writefile({ "-- test" }, path)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  return path
end

-- 1) Tek basina duran bos buffer silinmez: dosya yokken sekme kalmali.
empty.cleanup()
check(count_empty_listed() == 1, "acik dosya yokken [No Name] buffer korunur")

-- 2) Dosya acilinca arka planda kalan bos buffer silinir.
local leftover = vim.api.nvim_create_buf(true, false)
check(is_empty_listed(leftover), "test: bos buffer olusturuldu")
open_file()
vim.wait(500, function()
  return not vim.api.nvim_buf_is_valid(leftover)
end, 10)
check(not vim.api.nvim_buf_is_valid(leftover), "dosya acilinca bos [No Name] buffer silinir")
check(count_empty_listed() == 0, "dosya acikken bos buffer kalmaz")

-- 3) Degistirilmis bos buffer korunur.
local modified = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(modified, 0, -1, false, { "taslak" })
open_file()
vim.wait(300, function()
  return false
end, 10)
check(vim.api.nvim_buf_is_valid(modified), "degistirilmis anonim buffer silinmez")
vim.api.nvim_buf_delete(modified, { force = true })

-- 4) Icerigi olan ama degismemis buffer korunur.
local filled = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(filled, 0, -1, false, { "icerik" })
vim.bo[filled].modified = false
open_file()
vim.wait(300, function()
  return false
end, 10)
check(vim.api.nvim_buf_is_valid(filled), "icerigi olan anonim buffer silinmez")
vim.api.nvim_buf_delete(filled, { force = true })

-- 5) Baska pencerede gorunen bos buffer silinmez.
local shown = vim.api.nvim_create_buf(true, false)
vim.cmd("split")
vim.api.nvim_win_set_buf(0, shown)
open_file()
vim.wait(300, function()
  return false
end, 10)
check(vim.api.nvim_buf_is_valid(shown), "gorunen bos buffer silinmez")
vim.cmd("close")

-- 6) Yuklenmemis bos buffer da silinir.
local unloaded = vim.api.nvim_create_buf(true, false)
vim.cmd("bunload " .. unloaded)
vim.bo[unloaded].buflisted = true
open_file()
vim.wait(500, function()
  return not vim.api.nvim_buf_is_valid(unloaded)
end, 10)
check(not vim.api.nvim_buf_is_valid(unloaded), "yuklenmemis bos buffer silinir")

-- 7) Startup: bos sekme + dosya sekmesi birlikte acilirsa bos sekme kapanir.
local function reset_buffers()
  vim.cmd("silent! tabonly!")
  vim.cmd("silent! only!")
  vim.cmd("silent! %bwipeout!")
  vim.cmd("enew")
end

local function new_file()
  local path = vim.fn.tempname() .. ".lua"
  vim.fn.writefile({ "-- test" }, path)
  return path
end

reset_buffers()
local startup_file = new_file()
vim.cmd("tabnew " .. vim.fn.fnameescape(startup_file))
vim.cmd("tabprevious")
empty.cleanup_startup()
check(#vim.api.nvim_list_tabpages() == 1, "startup: bos sekme kapatilir")
check(
  vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()) == startup_file,
  "startup: dosya sekmesi aktif kalir"
)
check(count_empty_listed() == 0, "startup: dosya acikken bos buffer kalmaz")

-- 8) Startup: dosya yoksa [No Name] korunur.
reset_buffers()
empty.cleanup_startup()
check(count_empty_listed() == 1, "startup: dosya yokken [No Name] korunur")

-- 9) Bufferline filtresi: dosya varken bos buffer gizlenir.
local filter_file = new_file()
vim.cmd("edit " .. vim.fn.fnameescape(filter_file))
local hidden_empty = vim.api.nvim_create_buf(true, false)
check(
  empty.is_bufferline_visible(vim.api.nvim_get_current_buf()) == true,
  "bufferline: dosya sekmesi gorunur"
)
check(empty.is_bufferline_visible(hidden_empty) == false, "bufferline: dosya varken [No Name] gizlenir")
vim.api.nvim_buf_delete(hidden_empty, { force = true })
reset_buffers()
local only_empty = vim.api.nvim_get_current_buf()
check(empty.is_bufferline_visible(only_empty) == true, "bufferline: dosya yokken [No Name] gorunur")

-- 10) Placeholder normal, listed ve isimsiz buffer olmali; nofile scratch degil.
reset_buffers()
vim.cmd("silent! %bwipeout!")
local placeholder = empty.ensure_placeholder()
check(placeholder ~= nil, "placeholder: buffer olusturulur")
check(placeholder and vim.api.nvim_buf_is_valid(placeholder), "placeholder: gecerli buffer")
check(placeholder and vim.bo[placeholder].buftype == "", "placeholder: normal buffer (buftype bos)")
check(placeholder and vim.bo[placeholder].buflisted, "placeholder: listed")
check(placeholder and vim.api.nvim_buf_get_name(placeholder) == "", "placeholder: isimsiz")
check(placeholder and not vim.bo[placeholder].modified, "placeholder: degismemis")
check(placeholder and vim.api.nvim_win_get_buf(0) == placeholder, "placeholder: pencerede gorunur")

-- 11) Dosya acilinca placeholder silinir; yerine tek dosya sekmesi gelir.
local first_file = new_file()
vim.cmd("edit " .. vim.fn.fnameescape(first_file))
vim.wait(500, function()
  return count_empty_listed() == 0
end, 10)
check(
  not vim.api.nvim_buf_is_valid(placeholder) or vim.api.nvim_buf_get_name(placeholder) == first_file,
  "dosya acilinca placeholder silinir veya dosyaya donusur"
)
check(count_empty_listed() == 0, "dosya acikken placeholder kalmaz")
check(
  vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()) == first_file,
  "dosya placeholder'in yerine gelir"
)

-- 12) Ikinci dosya yeni sekme olarak eklenir; placeholder geri gelmez.
local second_file = new_file()
vim.cmd("edit " .. vim.fn.fnameescape(second_file))
vim.wait(300, function()
  return false
end, 10)
check(count_empty_listed() == 0, "ikinci dosyada placeholder olusmaz")
check(vim.bo[vim.fn.bufnr(first_file)].buflisted, "ilk dosya listede kalir")
check(vim.bo[vim.fn.bufnr(second_file)].buflisted, "ikinci dosya listede")

-- 13) Tek dosya kalinca kapatilirsa placeholder geri gelir.
empty.close_current_buffer()
vim.wait(300, function()
  return count_empty_listed() > 0
end, 10)
check(count_empty_listed() == 0, "bir dosya acikken placeholder olusmaz")

empty.close_current_buffer()
vim.wait(500, function()
  return count_empty_listed() == 1
end, 10)
check(count_empty_listed() == 1, "son dosya kapaninca placeholder olusur")
local restored = nil
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if is_empty_listed(buf) then
    restored = buf
    break
  end
end
check(restored ~= nil and vim.bo[restored].buftype == "", "geri gelen placeholder normal buffer")

-- 14) Placeholder varken yeni dosya acilinca scratch birikmez.
local third_file = new_file()
vim.cmd("edit " .. vim.fn.fnameescape(third_file))
vim.wait(500, function()
  return count_empty_listed() == 0
end, 10)
check(count_empty_listed() == 0, "placeholder uzerine dosya acilinca scratch birikmez")

if failures > 0 then
  io.write(string.format("\n%d/%d test basarisiz\n", failures, total))
  os.exit(1)
end

io.write(string.format("\n%d test gecti\n", total))
os.exit(0)
