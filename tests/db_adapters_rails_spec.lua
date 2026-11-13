-- tests/db_adapters_rails_spec.lua
-- Rails database.yml adaptörü.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/db_adapters_rails_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local rails = require("config.db.adapters.rails")

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

local fixture = vim.fn.fnamemodify(this, ":p:h") .. "/fixtures/db/rails"

eq(rails.detect(fixture).kind, "postgres", "development postgres secilir")
eq(rails.detect(fixture).dsn, "postgresql://postgres:secret@localhost:5432/app_dev", "rails dsn")

-- url: alani parcalardan once gelir
local base = vim.fn.tempname()
vim.fn.mkdir(base .. "/config", "p")
local f = assert(io.open(base .. "/config/database.yml", "w"))
f:write([[
development:
  adapter: postgresql
  url: mysql://u:p@h:3306/from_url
  database: ignored
]])
f:close()
eq(rails.detect(base).kind, "mysql", "url alani kazanir")
eq(rails.detect(base).dsn, "mysql://u:p@h:3306/from_url", "url dsn")

-- sqlite yolu koke gore mutlaklasir
local sqlite_root = vim.fn.tempname()
vim.fn.mkdir(sqlite_root .. "/config", "p")
local g = assert(io.open(sqlite_root .. "/config/database.yml", "w"))
g:write([[
development:
  adapter: sqlite3
  database: db/development.sqlite3
]])
g:close()
eq(rails.detect(sqlite_root).kind, "sqlite", "sqlite3 adapter")
eq(rails.detect(sqlite_root).dsn, "sqlite://" .. sqlite_root .. "/db/development.sqlite3", "sqlite yolu")

-- ERB desteklenmez
local erb_root = vim.fn.tempname()
vim.fn.mkdir(erb_root .. "/config", "p")
local h = assert(io.open(erb_root .. "/config/database.yml", "w"))
h:write([[
development:
  adapter: postgresql
  database: <%= ENV["DB_NAME"] %>
]])
h:close()
eq(rails.detect(erb_root), nil, "erb atlanir")

io.write(("%d/%d passed\n"):format(total - failures, total))
if failures > 0 then
  os.exit(1)
end
