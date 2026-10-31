-- tests/indent_sync_spec.lua
-- Formatter config -> buffer indent cozumleme testleri.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/indent_sync_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local sync = require("config.indent_sync")

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

local function eq(actual, expected, label)
  check(actual == expected, label .. " (beklenen: " .. tostring(expected) .. ", gelen: " .. tostring(actual) .. ")")
end

-- ── clang-format dump ────────────────────────────────────────────────────────

local clang_dump = [[
---
Language: Cpp
BasedOnStyle: LLVM
IndentWidth: 4
TabWidth: 8
UseTab: Never
ColumnLimit: 0
...
]]

local clang = sync.parse_clang_dump(clang_dump)
check(clang ~= nil, "clang dump parse edilir")
eq(clang and clang.shiftwidth, 4, "clang IndentWidth -> shiftwidth")
eq(clang and clang.tabstop, 8, "clang TabWidth -> tabstop")
eq(clang and clang.expandtab, true, "clang UseTab Never -> expandtab")

local clang_full = [[
---
Language: Cpp
ConstructorInitializerIndentWidth: 4
IndentWidth: 2
TabWidth: 8
UseTab: Never
ColumnLimit: 0
...
]]

local clang_real = sync.parse_clang_dump(clang_full)
eq(clang_real and clang_real.shiftwidth, 2, "clang dump: ConstructorInitializerIndentWidth IndentWidth sanilmaz")

local clang_tabs = sync.parse_clang_dump("IndentWidth: 4\nTabWidth: 4\nUseTab: ForIndentation\n")
eq(clang_tabs and clang_tabs.expandtab, false, "clang UseTab ForIndentation -> noexpandtab")

eq(sync.parse_clang_dump(""), nil, "bos clang dump -> nil (fallback)")
eq(sync.parse_clang_dump("UseTab: Never\n"), nil, "IndentWidth yok -> nil (fallback)")

-- ── prettier config ─────────────────────────────────────────────────────────

local p = sync.parse_prettier({ tabWidth = 3, useTabs = false })
eq(p and p.shiftwidth, 3, "prettier tabWidth -> shiftwidth")
eq(p and p.tabstop, 3, "prettier tabWidth -> tabstop")
eq(p and p.expandtab, true, "prettier useTabs false -> expandtab")

local p_tabs = sync.parse_prettier({ tabWidth = 4, useTabs = true })
eq(p_tabs and p_tabs.expandtab, false, "prettier useTabs true -> noexpandtab")

local p_default = sync.parse_prettier({})
eq(p_default and p_default.shiftwidth, 2, "prettier config bos -> varsayilan 2")

eq(sync.parse_prettier(nil), nil, "prettier config yok -> nil (fallback)")

-- ── stylua.toml ─────────────────────────────────────────────────────────────

local stylua = sync.parse_stylua('indent_type = "Tabs"\nindent_width = 2\n')
eq(stylua and stylua.expandtab, false, "stylua Tabs -> noexpandtab")
eq(stylua and stylua.shiftwidth, 2, "stylua indent_width -> shiftwidth")

local stylua_spaces = sync.parse_stylua('indent_type = "Spaces"\n')
eq(stylua_spaces and stylua_spaces.expandtab, true, "stylua Spaces -> expandtab")
eq(stylua_spaces and stylua_spaces.shiftwidth, 4, "stylua indent_width yok -> 4")

eq(sync.parse_stylua(""), nil, "bos stylua.toml -> nil (fallback)")

-- ── rustfmt.toml ────────────────────────────────────────────────────────────

local rust = sync.parse_rustfmt("tab_spaces = 2\nhard_tabs = true\n")
eq(rust and rust.expandtab, false, "rustfmt hard_tabs -> noexpandtab")
eq(rust and rust.shiftwidth, 2, "rustfmt tab_spaces -> shiftwidth")

local rust_default = sync.parse_rustfmt("tab_spaces = 2\n")
eq(rust_default and rust_default.expandtab, true, "rustfmt hard_tabs yok -> expandtab")
eq(rust_default and rust_default.shiftwidth, 2, "rustfmt tab_spaces -> shiftwidth (2)")

eq(sync.parse_rustfmt(""), nil, "bos rustfmt.toml -> nil (fallback)")

-- ── global fallback ─────────────────────────────────────────────────────────

local fallback = sync.fallback_opts()
eq(fallback.shiftwidth, 4, "global fallback shiftwidth = 4")
eq(fallback.tabstop, 4, "global fallback tabstop = 4")
eq(fallback.expandtab, true, "global fallback expandtab = true")

-- ── formatter argumanlari ───────────────────────────────────────────────────

--- Gecici dizin + dosya olustur.
local function temp_project(name, files)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  for fname, content in pairs(files or {}) do
    vim.fn.writefile(vim.split(content, "\n"), dir .. "/" .. fname)
  end
  local file = dir .. "/" .. name
  vim.fn.writefile({}, file)
  local buf = vim.fn.bufadd(file)
  vim.fn.bufload(buf)
  return buf, file, dir
end

local function buf_opts(buf, sw, et)
  vim.bo[buf].shiftwidth = sw
  vim.bo[buf].tabstop = sw
  vim.bo[buf].expandtab = et
end

-- Proje config yok: buffer ayarlari formatter'a gecer.
local plain_buf = temp_project("a.c", {})
vim.bo[plain_buf].filetype = "c"
buf_opts(plain_buf, 4, true)
local style = sync.clang_style(plain_buf)
check(style:match("IndentWidth: 4") ~= nil, "config yok -> clang stili IndentWidth 4")
check(style:match("UseTab: Never") ~= nil, "config yok -> clang stili UseTab Never")
check(style:match("ColumnLimit: 120") ~= nil, "config yok -> clang satir siniri 120")
check(style:match("ColumnLimit: 0") == nil, "config yok -> clang sinirsiz degil")

local p_args = sync.prettier_args(plain_buf)
eq(p_args[1], "--tab-width", "config yok -> prettier tab-width argumani")
eq(p_args[2], "4", "config yok -> prettier tab-width buffer'dan")
eq(p_args[3], "--use-tabs=false", "config yok -> prettier expandtab")

local function has_arg(args, needle)
  for _, a in ipairs(args) do
    if a == needle then
      return true
    end
  end
  return false
end

check(has_arg(p_args, "--print-width"), "config yok -> prettier print-width gecilir")
local width_idx = nil
for i, a in ipairs(p_args) do
  if a == "--print-width" then
    width_idx = i
  end
end
eq(width_idx and p_args[width_idx + 1], "120", "config yok -> prettier print-width 120")

-- printWidth proje config'inde varsa dokunulmaz
local pw_buf = temp_project("pw.js", { [".prettierrc.json"] = '{"printWidth": 100, "tabWidth": 2}' })
vim.bo[pw_buf].filetype = "javascript"
check(not has_arg(sync.prettier_args(pw_buf), "--print-width"), "config printWidth -> arguman yok")

-- printWidth yoksa 120 varsayilani uygulanir
local npw_buf = temp_project("npw.js", { [".prettierrc.json"] = '{"tabWidth": 2}' })
vim.bo[npw_buf].filetype = "javascript"
check(has_arg(sync.prettier_args(npw_buf), "--print-width"), "config printWidth yok -> 120 uygulanir")

-- rustfmt: max_width yoksa 120, varsa dokunulmaz
local rust_args = sync.rustfmt_width_args(plain_buf and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(plain_buf), ":h"))
eq(rust_args[1], "--config", "rustfmt config yok -> --config gecilir")
eq(rust_args[2], "max_width=120", "rustfmt config yok -> max_width=120")

local rust_cfg_dir = vim.fn.tempname()
vim.fn.mkdir(rust_cfg_dir, "p")
vim.fn.writefile({ "max_width = 100" }, rust_cfg_dir .. "/rustfmt.toml")
eq(#sync.rustfmt_width_args(rust_cfg_dir), 0, "rustfmt max_width var -> arguman yok")

local rust_cfg_dir2 = vim.fn.tempname()
vim.fn.mkdir(rust_cfg_dir2, "p")
vim.fn.writefile({ 'edition = "2021"' }, rust_cfg_dir2 .. "/rustfmt.toml")
eq(sync.rustfmt_width_args(rust_cfg_dir2)[2], "max_width=120", "rustfmt max_width yok -> 120")

eq(#sync.rustfmt_width_args(vim.fn.tempname()), 2, "rustfmt.toml yok -> 120")

-- Proje config var: formatter kendi kuralini uygular.
local cfg_buf, _, cfg_dir = temp_project("b.c", {
  [".clang-format"] = "BasedOnStyle: LLVM\nIndentWidth: 2\nTabWidth: 8\nUseTab: Always\n",
})
vim.bo[cfg_buf].filetype = "c"
eq(sync.clang_style(cfg_buf), "-style=file", "config var -> clang -style=file")

local resolved = sync.resolve_for(cfg_buf)
eq(resolved and resolved.shiftwidth, 2, "proje .clang-format -> shiftwidth 2")
eq(resolved and resolved.tabstop, 8, "proje .clang-format -> tabstop 8")
eq(resolved and resolved.expandtab, false, "proje .clang-format UseTab Always -> noexpandtab")

-- Proje config yokken cozumleyici mevcut ayari korur (fallback = nil).
local keep = sync.resolve_for(plain_buf)
eq(keep, nil, "config yok -> resolve nil (global/editorconfig korunur)")

-- stilua argumanlari
local lua_buf = temp_project("x.lua", {})
vim.bo[lua_buf].filetype = "lua"
buf_opts(lua_buf, 4, true)
local s_args = sync.stylua_args(lua_buf)
eq(s_args[1], "--indent-width", "config yok -> stylua indent-width argumani")
eq(s_args[2], "4", "config yok -> stylua indent-width buffer'dan")

local lua_cfg_buf = temp_project("y.lua", { ["stylua.toml"] = 'indent_type = "Spaces"\nindent_width = 2\n' })
vim.bo[lua_cfg_buf].filetype = "lua"
eq(#sync.stylua_args(lua_cfg_buf), 0, "stylua.toml var -> arguman yok")

-- JS prettier config (node resolveConfig yolu)
local js_cfg_buf = temp_project("z.js", {
  [".prettierrc.cjs"] = "module.exports = { tabWidth: 2, useTabs: false };",
})
vim.bo[js_cfg_buf].filetype = "javascript"
local js_opts = sync.resolve_for(js_cfg_buf)
eq(js_opts and js_opts.shiftwidth, 2, "proje .prettierrc.cjs -> shiftwidth 2")
eq(js_opts and js_opts.expandtab, true, "proje .prettierrc.cjs useTabs false -> expandtab")
local js_args = sync.prettier_args(js_cfg_buf)
check(not has_arg(js_args, "--tab-width"), "prettier config var -> tab-width override yok")
check(has_arg(js_args, "--print-width"), "prettier config printWidth yok -> 120")

-- ── bozuk girdi asla hata firlatmaz ─────────────────────────────────────────

local ok1 = pcall(sync.parse_clang_dump, "%%% bozuk ???")
check(ok1, "bozuk clang dump hata firlatmaz")
local ok2 = pcall(sync.parse_prettier, { tabWidth = "abc" })
check(ok2, "bozuk prettier tabWidth hata firlatmaz")
local ok3 = pcall(sync.parse_rustfmt, "hard_tabs = belki")
check(ok3, "bozuk rustfmt hata firlatmaz")

io.write(string.format("\n%d/%d gecti, %d basarisiz\n", total - failures, total, failures))
if failures > 0 then
  os.exit(1)
end
