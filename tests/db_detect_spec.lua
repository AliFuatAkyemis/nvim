-- tests/db_detect_spec.lua
-- Tespit çekirdeği: öncelik, cache, komutlar.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/db_detect_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local detect = require("config.db.detect")

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

local function project(files)
  local base = vim.fn.tempname()
  vim.fn.mkdir(base, "p")
  local marker = assert(io.open(base .. "/pom.xml", "w"))
  marker:write("<project/>")
  marker:close()
  for path, content in pairs(files) do
    vim.fn.mkdir(vim.fs.dirname(base .. "/" .. path), "p")
    local f = assert(io.open(base .. "/" .. path, "w"))
    f:write(content)
    f:close()
  end
  return base
end

local function open(path)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  return vim.api.nvim_get_current_buf()
end

local spring_root = project({
  ["src/main/resources/application.properties"] = "spring.datasource.url=jdbc:postgresql://h:5432/springdb\n",
})
local dotenv_root = project({
  ["src/main/resources/application.properties"] = "spring.datasource.url=jdbc:postgresql://h:5432/springdb\n",
  [".env.local"] = "DATABASE_URL=mysql://u:p@h:3306/envdb\n",
})
local empty_root = project({})

local spring_buf = open(spring_root .. "/a.sql")
local dotenv_buf = open(dotenv_root .. "/b.sql")
local empty_buf = open(empty_root .. "/c.sql")

detect.invalidate()
vim.env.DATABASE_URL = "postgresql://env@h/envdb"
eq(detect.connection(spring_buf).source, "env:DATABASE_URL", "env > spring")
vim.env.DATABASE_URL = nil

detect.invalidate()
eq(detect.connection(dotenv_buf).source, "dotenv:.env.local", "dotenv > spring")

detect.invalidate()
eq(detect.connection(spring_buf).kind, "postgres", "spring bulunur")

detect.invalidate()
eq(detect.connection(empty_buf), nil, "config yoksa nil")

-- cache: adaptör sonucu degisse de invalidate olmadan ayni kalir
local cached = detect.connection(spring_buf)
vim.fn.writefile({ "DATABASE_URL=mysql://u:p@h/db" }, spring_root .. "/.env")
eq(detect.connection(spring_buf), cached, "cache doner")
detect.invalidate()
eq(detect.connection(spring_buf).kind, "mysql", "invalidate sonrasi yeniden okunur")

detect.setup()
eq(vim.fn.exists(":DbDetectInfo"), 2, "DbDetectInfo komutu")
eq(vim.fn.exists(":DbDetectRefresh"), 2, "DbDetectRefresh komutu")

io.write(("%d/%d passed\n"):format(total - failures, total))
if failures > 0 then
  os.exit(1)
end
