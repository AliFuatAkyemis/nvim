-- tests/db_types_spec.lua
-- Dialekt tip kaynakları.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/db_types_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local types = require("config.db.types")

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

local pg = types.normalize({ "character varying", "integer", "uuid" }, "postgres")
check(vim.tbl_contains(pg, "VARCHAR"), "varchar alias")
check(vim.tbl_contains(pg, "VARCHAR(255)"), "varchar(255) alias")
check(vim.tbl_contains(pg, "INT"), "int alias")
check(vim.tbl_contains(pg, "UUID"), "uuid buyuk harf")
local unique = {}
for _, name in ipairs(pg) do
  unique[name] = true
end
eq(vim.tbl_count(unique), #pg, "dedupe")

check(#types.static("mysql") > 10, "mysql statik liste")
check(vim.tbl_contains(types.static("mysql"), "DATETIME"), "mysql datetime")
check(#types.static("sqlite") > 5, "sqlite statik liste")
check(vim.tbl_contains(types.static("sqlite"), "INTEGER"), "sqlite integer")
check(types.static(nil)[1] ~= nil, "bilinmeyen turde varsayilan PG")
eq(types.static("postgres")[1] ~= nil, true, "postgres statik")

check(type(types.postgres_query) == "string" and types.postgres_query:find("pg_type", 1, true) ~= nil, "pg sorgusu")

io.write(("%d/%d passed\n"):format(total - failures, total))
if failures > 0 then
  os.exit(1)
end
