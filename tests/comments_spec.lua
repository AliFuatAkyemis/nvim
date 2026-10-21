-- tests/comments_spec.lua
-- gc yorum toggle davranislari icin headless entegrasyon testi.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/comments_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local comments = require("config.comments")

vim.bo.filetype = "java"
vim.bo.commentstring = "// %s"
vim.bo.expandtab = true

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

local function set_lines(lines)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
end

local function lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function visual(mode_, srow, scol, erow, ecol)
  vim.fn.setpos("'<", { 0, srow, scol, 0 })
  vim.fn.setpos("'>", { 0, erow, ecol, 0 })
  vim.api.nvim_win_set_cursor(0, { srow, math.max(scol - 1, 0) })
  comments.toggle_visual(mode_)
end

-- Normal mod: tek satir //
do
  set_lines({ "    int a = 1;" })
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  comments.toggle_line()
  check(lines()[1] == "    // int a = 1;", "normal: // eklenir")
  comments.toggle_line()
  check(lines()[1] == "    int a = 1;", "normal: // geri alinir")
end

-- Visual line: tek satir //
do
  set_lines({ "    int a = 1;" })
  visual("V", 1, 1, 1, 1)
  check(lines()[1] == "    // int a = 1;", "visual line 1 satir: //")
  visual("V", 1, 1, 1, 1)
  check(lines()[1] == "    int a = 1;", "visual line 1 satir: // geri alinir")
end

-- Visual line: cok satir -> formatter tarzi blok
do
  local original = { "    int a = 1;", "    int b = 2;" }
  set_lines(original)
  visual("V", 1, 1, 2, 1)
  check(
    vim.deep_equal(lines(), {
      "    /*",
      "     * int a = 1;",
      "     * int b = 2;",
      "     */",
    }),
    "visual line: blok + yildiz stili"
  )
  visual("V", 1, 1, 4, 1)
  check(vim.deep_equal(lines(), original), "visual line: blok geri alinir")
end

-- Formatter sonrasi bosluk/tab varyasyonlari da temizlenmeli
do
  set_lines({
    "    /*",
    "     *int a = 1;",
    "     *\tint b = 2;",
    "     */",
  })
  visual("V", 1, 1, 4, 1)
  check(
    vim.deep_equal(lines(), { "    int a = 1;", "    int b = 2;" }),
    "visual line: formatter varyantlari temizlenir"
  )
end

-- Visual line: // ile yorumlanmis blok geri alinir
do
  set_lines({ "    // int a = 1;", "    // int b = 2;" })
  visual("V", 1, 1, 2, 1)
  check(
    vim.deep_equal(lines(), { "    int a = 1;", "    int b = 2;" }),
    "visual line: // blok geri alinir"
  )
end

-- Visual block: her satirda secili parca
do
  set_lines({ "foo(a, b);", "bar(c, d);" })
  visual("\22", 1, 5, 2, 8)
  check(
    vim.deep_equal(lines(), { "foo(/* a, b */);", "bar(/* c, d */);" }),
    "visual block: secili parcalar sarilir"
  )
  visual("\22", 1, 5, 2, 8)
  check(
    vim.deep_equal(lines(), { "foo(a, b);", "bar(c, d);" }),
    "visual block: ayni secimle geri alinir"
  )
end

-- Visual block: secim yorumun icinden gecse de geri alinmali
do
  set_lines({ "foo(/* a, b */);" })
  visual("\22", 1, 7, 1, 9)
  check(lines()[1] == "foo(a, b);", "visual block: icten secimle geri alinir")
end

-- Visual block: toggle sonrasi birakilan marklar gv ile geri alinabilmeli
do
  local original = { "foo(a, b);", "bar(c, d);" }
  set_lines(original)
  visual("\22", 1, 5, 2, 8)
  comments.toggle_visual("\22")
  check(vim.deep_equal(lines(), original), "visual block: gv markalari geri alir")
end

-- Visual block: kisa satirlar atlanir
do
  set_lines({ "foo(a, b);", "x" })
  visual("\22", 1, 5, 2, 8)
  check(
    vim.deep_equal(lines(), { "foo(/* a, b */);", "x" }),
    "visual block: secim disi satir korunur"
  )
end

-- Sadece gc kalmali: yerlesik gcc/gbc ve digerleri kaldirilir
do
  comments.setup()
  check(vim.fn.maparg("gc", "n") ~= "", "setup: normal gc bagli")
  check(vim.fn.maparg("gc", "x") ~= "", "setup: visual gc bagli")
  check(vim.fn.maparg("gcc", "n") == "", "setup: gcc kaldirildi")
  check(vim.fn.maparg("gbc", "n") == "", "setup: gbc kaldirildi")
  check(vim.fn.maparg("gco", "n") == "", "setup: gco kaldirildi")
end

io.write(("%d/%d passed\n"):format(total - failures, total))
if failures > 0 then
  os.exit(1)
end
