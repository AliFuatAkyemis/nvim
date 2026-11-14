-- tests/db_adapters_django_spec.lua
-- Django settings.py adaptörü.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/db_adapters_django_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local django = require("config.db.adapters.django")

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

local fixtures = vim.fn.fnamemodify(this, ":p:h") .. "/fixtures/db/django"
local env_root = vim.fn.fnamemodify(this, ":p:h") .. "/fixtures/db/django_env"

eq(django.detect(fixtures).kind, "postgres", "django engine")
eq(django.detect(fixtures).dsn, "postgresql://postgres:secret@127.0.0.1:5432/appdb", "django dsn")
eq(django.detect(env_root).kind, "mysql", "django DATABASE_URL")

-- sqlite BASE_DIR
local sqlite_root = vim.fn.tempname()
vim.fn.mkdir(sqlite_root, "p")
local f = assert(io.open(sqlite_root .. "/settings.py", "w"))
f:write([[
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": BASE_DIR / "db.sqlite3",
    }
}
]])
f:close()
eq(django.detect(sqlite_root).kind, "sqlite", "django sqlite")
eq(django.detect(sqlite_root).dsn, "sqlite://" .. sqlite_root .. "/db.sqlite3", "django sqlite yolu")

io.write(("%d/%d passed\n"):format(total - failures, total))
if failures > 0 then
  os.exit(1)
end
