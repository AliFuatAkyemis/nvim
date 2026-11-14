-- tests/db_adapters_spring_spec.lua
-- Spring Boot datasource adaptörü.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/db_adapters_spring_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local spring = require("config.db.adapters.spring")

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
local props_root = fixtures .. "/spring_props"
local yml_root = fixtures .. "/spring_yml"

eq(spring.detect(props_root).kind, "postgres", "properties jdbc postgresql")
eq(spring.detect(props_root).dsn, "postgresql://postgres:secret@127.0.0.1:5432/expensetracker", "properties dsn")
eq(spring.detect(yml_root).kind, "mysql", "yml jdbc mysql")

vim.env.SPRING_TEST_DB = "placedb"
local props = spring.read_properties(props_root .. "/src/main/resources/application.properties")
eq(props["spring.datasource.username"], "postgres", "properties okuma")
eq(
  spring.read_properties(props_root .. "/src/main/resources/application.properties").name,
  nil,
  "bilinmeyen anahtar yok"
)
vim.env.SPRING_TEST_DB = nil

-- placeholder cozumu
local base = vim.fn.tempname()
vim.fn.mkdir(base .. "/src/main/resources", "p")
local f = assert(io.open(base .. "/src/main/resources/application.properties", "w"))
f:write("spring.datasource.url=jdbc:postgresql://h:5432/${DB_NAME:fallback}\n")
f:close()
eq(spring.detect(base).dsn, "postgresql://h:5432/fallback", "placeholder varsayilan")

io.write(("%d/%d passed\n"):format(total - failures, total))
if failures > 0 then
  os.exit(1)
end
