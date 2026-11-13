-- tests/db_lsp_spec.lua
-- LSP yardımcıları: env, sqls bağlantısı, syntax override.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/db_lsp_spec.lua

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

local mysql = lsp.sqls_connection({ kind = "mysql", dsn = "mysql://u:p@h:3306/db" })
eq(mysql and mysql.driver, "mysql", "mysql sqls driver")
eq(mysql and mysql.dataSourceName, "u:p@tcp(h:3306)/db", "mysql sqls dataSourceName")

local sqlite = lsp.sqls_connection({ kind = "sqlite", dsn = "sqlite:///tmp/x.db" })
eq(sqlite and sqlite.driver, "sqlite3", "sqlite sqls driver")
eq(sqlite and sqlite.dataSourceName, "/tmp/x.db", "sqlite sqls path")

eq(lsp.sqls_connection({ kind = "postgres", dsn = "postgresql://u@h/db" }), nil, "pg sqls'e verilmez")

eq(lsp.pgls_env({ kind = "postgres", dsn = "postgresql://u@h/db" }, { A = "1" }).A, "1", "mevcut env korunur")
eq(
  lsp.pgls_env({ kind = "postgres", dsn = "postgresql://u@h/db" }, {}).DATABASE_URL,
  "postgresql://u@h/db",
  "dsn env'e eklenir"
)
eq(lsp.pgls_env({ kind = "mysql", dsn = "mysql://u@h/db" }, {}).DATABASE_URL, nil, "postgres degilse eklenmez")
eq(lsp.pgls_env(nil, {}).DATABASE_URL, nil, "baglanti yoksa env eklenmez")

eq(lsp.override("postgres"), "postgres", "postgres override")
eq(lsp.override("mysql"), "mysql", "mysql override")
eq(lsp.override("sqlite"), nil, "sqlite override yok")
eq(lsp.override(nil), nil, "baglantisiz override yok")

io.write(("%d/%d passed\n"):format(total - failures, total))
if failures > 0 then
  os.exit(1)
end
