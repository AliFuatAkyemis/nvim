-- tests/db_yaml_spec.lua
-- Minimal YAML okuyucu testleri.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/db_yaml_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local yaml = require("config.db.yaml")

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

local t = yaml.parse([[
spring:
  datasource:
    url: jdbc:postgresql://h:5432/db
    username: postgres
  profiles:
    active: dev
]])

eq(t.spring.datasource.url, "jdbc:postgresql://h:5432/db", "ic ice anahtar")
eq(t.spring.datasource.username, "postgres", "kardes anahtar")
eq(t.spring.profiles.active, "dev", "ucuncu seviye")
eq(yaml.parse("a:\n  b: 'x' # yorum").a.b, "x", "tirnak ve yorum")
check(yaml.parse("bozuk: [") ~= nil, "bozuk yaml nil dondurmez")

io.write(("%d/%d passed\n"):format(total - failures, total))
if failures > 0 then
  os.exit(1)
end
