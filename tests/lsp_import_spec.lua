-- tests/lsp_import_spec.lua
-- Alt+Enter ile eksik import ekleme: diagnostic hedefi, import filtresi, keymap.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/lsp_import_spec.lua

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

local function finish()
  io.write(string.format("\n%d/%d gecti, %d basarisiz\n", total - failures, total, failures))
  os.exit(failures == 0 and 0 or 1)
end

local ok, lsp_import = pcall(require, "config.lsp_import")
if not ok then
  io.write("FAIL - config.lsp_import modulu yuklenemedi\n")
  failures = failures + 1
  finish()
end

-- ------------------------------------------------------ diagnostic hedefi
local bufnr = vim.api.nvim_get_current_buf()
local ns = vim.api.nvim_create_namespace("lsp_import_test")

local function setup(lines, diagnostics)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.diagnostic.reset(ns, bufnr)
  vim.diagnostic.set(ns, bufnr, diagnostics or {})
end

local function diag(lnum, col, end_col)
  return {
    lnum = lnum,
    col = col,
    end_lnum = lnum,
    end_col = end_col,
    message = "Cannot find name",
    severity = vim.diagnostic.severity.ERROR,
  }
end

setup({ "const value = missing;" }, { diag(0, 14, 21) })

check(
  vim.deep_equal(lsp_import.target_position(bufnr, { 1, 20 }, false), { 1, 14 }),
  "normal: son karakterden kelime basina"
)
check(
  vim.deep_equal(lsp_import.target_position(bufnr, { 1, 14 }, false), { 1, 14 }),
  "normal: ilk karakterde kelime basina"
)
check(
  vim.deep_equal(lsp_import.target_position(bufnr, { 1, 17 }, false), { 1, 14 }),
  "normal: kelime ortasinda kelime basina"
)

-- Insert modda imlec ekleme noktasidir: kelimenin sonunda col == end_col olur.
check(
  vim.deep_equal(lsp_import.target_position(bufnr, { 1, 21 }, true), { 1, 14 }),
  "insert: kelime sonunda kelime basina"
)
check(
  vim.deep_equal(lsp_import.target_position(bufnr, { 1, 14 }, true), { 1, 14 }),
  "insert: ilk karakterde kelime basina"
)
check(
  vim.deep_equal(lsp_import.target_position(bufnr, { 1, 18 }, true), { 1, 14 }),
  "insert: kelime ortasinda kelime basina"
)

-- Ayni satirda iki diagnostic varsa imlece en yakin olan secilir.
setup({ "foo bar" }, { diag(0, 0, 3), diag(0, 4, 7) })
check(vim.deep_equal(lsp_import.target_position(bufnr, { 1, 5 }, false), { 1, 4 }), "coklu diagnostic: en yakin kelime")
check(
  vim.deep_equal(lsp_import.target_position(bufnr, { 1, 7 }, true), { 1, 4 }),
  "coklu diagnostic: insert kelime sonu"
)

-- Diagnostic yoksa veya imlec alti cizili kelimede degilse hedef yok.
setup({ "foo bar" }, { diag(0, 0, 3) })
check(lsp_import.target_position(bufnr, { 1, 6 }, false) == nil, "kelime disinda hedef yok")
setup({ "foo bar" }, {})
check(lsp_import.target_position(bufnr, { 1, 0 }, false) == nil, "diagnostic yoksa hedef yok")

-- -------------------------------------------------------- import filtresi
check(lsp_import.is_import_action({ title = "Import 'foo' from './foo'" }), "TS import aksiyonu gecer")
check(lsp_import.is_import_action({ title = 'Add import from "react"' }), "add import aksiyonu gecer")
check(lsp_import.is_import_action({ title = "IMPORT 'Foo'" }), "buyuk harfli import gecer")
check(lsp_import.is_import_action({ title = "Import 'Foo' (org.example)" }), "Java import aksiyonu gecer")
check(not lsp_import.is_import_action({ title = "Remove unused import" }), "unused import kaldirma elenir")
check(not lsp_import.is_import_action({ title = "Organize imports" }), "organize imports elenir")
check(not lsp_import.is_import_action({ title = "Optimize imports" }), "optimize imports elenir")
check(not lsp_import.is_import_action({ title = "Extract variable" }), "alakasiz aksiyon elenir")
check(not lsp_import.is_import_action({ title = "" }), "basliksiz aksiyon elenir")
-- Baslikta proje adi gectigi icin "import" iceren alakasiz aksiyon elenmeli.
check(not lsp_import.is_import_action({
  title = 'Show compiler optimization details for "lsp-import-it-go"',
  kind = "source.toggleCompilerOptDetails",
}), "import kelimesi gecen source aksiyonu elenir")
check(
  lsp_import.is_import_action({ title = 'Add import:  "fmt"', kind = "quickfix" }),
  "quickfix import aksiyonu gecer"
)

-- ---------------------------------------------------- akilli import secimi
-- Ayni sembol icin birden fazla import adayi varsa: dosyada zaten kullanilan
-- import yolu ile eslesen aday once gelir; hicbiri eslesmezse ilk aday.
local candidates = {
  { action = { title = "Import 'foo' from './other'", kind = "quickfix" }, client_id = 1 },
  { action = { title = "Import 'foo' from './dep'", kind = "quickfix" }, client_id = 1 },
}
local picked = lsp_import.pick_import_action(candidates, { "import { bar } from './dep'", "const x = foo" })
check(picked ~= nil and picked.action.title == "Import 'foo' from './dep'", "akilli secim: mevcut import yolu eslesir")

local java_candidates = {
  { action = { title = "Import 'ArrayList' (java.util.concurrent)", kind = "quickfix" }, client_id = 1 },
  { action = { title = "Import 'ArrayList' (java.util)", kind = "quickfix" }, client_id = 1 },
}
picked = lsp_import.pick_import_action(java_candidates, { "import java.util.List;", "List<ArrayList> x;" })
check(picked ~= nil and picked.action.title == "Import 'ArrayList' (java.util)", "akilli secim: Java mevcut paket")

local rust_candidates = {
  { action = { title = "Import `foo` from `crate::other`", kind = "quickfix" }, client_id = 1 },
  { action = { title = "Import `foo` from `crate::dep`", kind = "quickfix" }, client_id = 1 },
}
picked = lsp_import.pick_import_action(rust_candidates, { "use crate::dep::bar;", "let x = foo;" })
check(picked ~= nil and picked.action.title == "Import `foo` from `crate::dep`", "akilli secim: Rust mevcut use yolu")

-- Hicbir aday mevcut import satiriyla eslesmiyorsa ilk aday.
local no_match = {
  { action = { title = "Import 'foo' from './a'", kind = "quickfix" }, client_id = 1 },
  { action = { title = "Import 'foo' from './b'", kind = "quickfix" }, client_id = 1 },
}
picked = lsp_import.pick_import_action(no_match, { "const x = foo" })
check(picked ~= nil and picked.action.title == "Import 'foo' from './a'", "akilli secim: eslesme yoksa ilk aday")

check(lsp_import.pick_import_action({}, { "const x = foo" }) == nil, "akilli secim: aday yoksa nil")

-- ------------------------------------------------- code action sonuc toplama
local results = {
  [1] = { result = { { title = "Import 'foo' from './dep'", kind = "quickfix" } } },
  [2] = {
    result = {
      { title = "Organize imports", kind = "source.organizeImports" },
      { title = "Extract variable", kind = "refactor.extract" },
    },
  },
  [3] = { err = { message = "boom" }, result = nil },
}
local entries = lsp_import.action_entries(results)
check(#entries == 3, "action_entries: tum sonuclar toplanir")
check(entries[1].client_id == 1 and entries[2].client_id == 2, "action_entries: client_id korunur")
check(lsp_import.action_entries({}) ~= nil and #lsp_import.action_entries({}) == 0, "action_entries: bos sonuc")

-- ---------------------------------------------------------------- keymap
vim.g.mapleader = " "
package.preload["telescope.builtin"] = function()
  return { find_files = function() end, live_grep = function() end }
end
dofile(root .. "/lua/config/keymaps.lua")

local function map_desc(lhs, mode)
  return vim.fn.maparg(lhs, mode, false, true).desc
end
check(map_desc("<M-CR>", "n") == "Eksik import ekle (LSP)", "normal <M-CR> import mapping")
check(map_desc("<M-CR>", "i") == "Eksik import ekle (LSP)", "insert <M-CR> import mapping")
check(map_desc("<C-M-CR>", "n") == "LSP code action listesi", "normal <C-M-CR> action list mapping")
check(map_desc("<C-M-CR>", "i") == "LSP code action listesi", "insert <C-M-CR> action list mapping")

finish()
