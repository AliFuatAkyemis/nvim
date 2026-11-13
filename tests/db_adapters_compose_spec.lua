-- tests/db_adapters_compose_spec.lua
-- docker-compose adaptörü + adaptör kaydı.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/db_adapters_compose_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local compose = require("config.db.adapters.compose")
local adapters = require("config.db.adapters.init")

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

local fixture = vim.fn.fnamemodify(this, ":p:h") .. "/fixtures/db/compose"

eq(compose.detect(fixture).kind, "postgres", "compose postgres")
eq(compose.detect(fixture).dsn, "postgresql://postgres:secret@localhost:55432/appdb", "compose port mapping")

eq(#adapters.order, 7, "yedi adaptor")
eq(adapters.order[1], "env", "env ilk")
eq(adapters.order[7], "compose", "compose son")

-- port yayinlanmamissa nil
local noport = vim.fn.tempname()
vim.fn.mkdir(noport, "p")
local f = assert(io.open(noport .. "/compose.yml", "w"))
f:write([[
services:
  db:
    environment:
      POSTGRES_DB: appdb
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: secret
]])
f:close()
eq(compose.detect(noport), nil, "port yoksa atlanir")

-- DATABASE_URL environment'ta dogrudan kullanilir
local direct = vim.fn.tempname()
vim.fn.mkdir(direct, "p")
local g = assert(io.open(direct .. "/compose.yml", "w"))
g:write([[
services:
  app:
    environment:
      DATABASE_URL: mysql://u:p@db:3306/app
]])
g:close()
eq(compose.detect(direct).kind, "mysql", "compose DATABASE_URL")

io.write(("%d/%d passed\n"):format(total - failures, total))
if failures > 0 then
  os.exit(1)
end
