-- tests/db_adapters_env_spec.lua
-- env + dotenv adaptörleri ve güvenli dosya okuma.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/db_adapters_env_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local env = require("config.db.adapters.env")
local dotenv = require("config.db.adapters.dotenv")
local fs = require("config.db.fs")

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

local fixture = vim.fn.fnamemodify(this, ":p:h") .. "/fixtures/db/dotenv"

vim.env.DATABASE_URL = "postgresql://u:p@h:5432/db"
eq(env.detect("/tmp").kind, "postgres", "env DATABASE_URL")
eq(env.detect("/tmp").source, "env:DATABASE_URL", "env kaynak etiketi")
vim.env.DATABASE_URL = nil

vim.env.PGHOST = "127.0.0.1"
vim.env.PGDATABASE = "testdb"
eq(env.detect("/tmp").kind, "postgres", "env PG* parcalari")
eq(env.detect("/tmp").dsn, "postgresql://" .. (vim.env.USER or "") .. "@127.0.0.1/testdb", "env PG* dsn")
vim.env.PGHOST = nil
vim.env.PGDATABASE = nil

eq(dotenv.detect(fixture).kind, "mysql", "dotenv DATABASE_URL")
eq(dotenv.detect(fixture).source, "dotenv:.env.local", "dotenv .env.local kazanir")
eq(dotenv.lookup("DATABASE_URL", fixture), "mysql://u:p@h/db", "dotenv lookup")

-- Kök dışına symlink reddedilir
local base = vim.fn.tempname()
vim.fn.mkdir(base, "p")
local outside = base .. "_outside.txt"
local f = assert(io.open(outside, "w"))
f:write("secret")
f:close()
local link = base .. "/link.txt"
vim.uv.fs_symlink(outside, link)
eq(fs.read(link, base), nil, "kok disi symlink reddedilir")

io.write(("%d/%d passed\n"):format(total - failures, total))
if failures > 0 then
  os.exit(1)
end
