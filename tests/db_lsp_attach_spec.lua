-- tests/db_lsp_attach_spec.lua
-- DB türüne göre LSP seçimi.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/db_lsp_attach_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local lsp = require("config.db.lsp")

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

eq(lsp.attach_kind("postgres"), "postgres_lsp", "pg -> pgls")
eq(lsp.attach_kind("mysql"), "sqls", "mysql -> sqls")
eq(lsp.attach_kind("sqlite"), "sqls", "sqlite -> sqls")
eq(lsp.attach_kind(nil), nil, "baglanti yoksa lsp yok")

io.write(("%d/%d passed\n"):format(total - failures, total))
if failures > 0 then
  os.exit(1)
end
