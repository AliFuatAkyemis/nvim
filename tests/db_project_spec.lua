-- tests/db_project_spec.lua
-- Proje kökü tespiti.
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/db_project_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local project = require("config.db.project")

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

local base = vim.fn.tempname()
local function mkdir(path)
  vim.fn.mkdir(path, "p")
end
local function touch(path)
  mkdir(vim.fs.dirname(path))
  local f = assert(io.open(path, "w"))
  f:write("")
  f:close()
end

local function open(path)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  return vim.api.nvim_get_current_buf()
end

-- pom.xml işareti
local proj = base .. "/proj"
touch(proj .. "/pom.xml")
touch(proj .. "/src/main/x.sql")
eq(project.root(open(proj .. "/src/main/x.sql")), proj, "pom.xml kok")

-- package.json işareti
local nodep = base .. "/node/p"
touch(nodep .. "/package.json")
touch(nodep .. "/y.sql")
eq(project.root(open(nodep .. "/y.sql")), nodep, "package.json kok")

-- işaret yoksa dosya dizini
local solo = base .. "/solo"
touch(solo .. "/z.sql")
eq(project.root(open(solo .. "/z.sql")), solo, "isaretsiz dosya dizini")

io.write(("%d/%d passed\n"):format(total - failures, total))
if failures > 0 then
  os.exit(1)
end
