-- tests/db_adapters_prisma_spec.lua
-- Prisma schema.prisma adaptörü.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/db_adapters_prisma_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local prisma = require("config.db.adapters.prisma")

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

local fixtures = vim.fn.fnamemodify(this, ":p:h") .. "/fixtures/db"
local sqlite_root = fixtures .. "/prisma"
local env_root = fixtures .. "/prisma_env"

eq(prisma.detect(sqlite_root).kind, "sqlite", "prisma sqlite")
eq(prisma.detect(sqlite_root).dsn, "sqlite://" .. sqlite_root .. "/prisma/dev.db", "file: yolu schema dizinine gore")
eq(prisma.detect(env_root).kind, "postgres", "prisma env(...) cozulur")
eq(prisma.detect(env_root).dsn, "postgresql://user:pass@127.0.0.1:5432/envdb", "env dsn")

io.write(("%d/%d passed\n"):format(total - failures, total))
if failures > 0 then
  os.exit(1)
end
