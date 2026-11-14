-- tests/db_sql_assist_spec.lua
-- db_types cmp kaynağı + snippet kaydı (cmp/LuaSnip stub'lanır).
--
-- Kosum (depo kokunden):
--   nvim --headless -u NONE -l tests/db_sql_assist_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local registered = {}
local snippets = {}
package.loaded["cmp"] = {
  register_source = function(name)
    registered[name] = true
  end,
}
package.loaded["cmp.types"] = { lsp = { CompletionItemKind = { TypeParameter = 25, Keyword = 14 } } }
package.loaded["luasnip"] = {
  snippet = function(opts, body)
    return { trigger = opts.trig, body = body }
  end,
  text_node = function(value)
    return value
  end,
  insert_node = function(_, default)
    return default or ""
  end,
  add_snippets = function(ft, list)
    snippets[ft] = list
  end,
}

local assist = require("config.sql_assist")

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

vim.bo.filetype = "sql"
local src = assist.source.new()

local function items(lines, row)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  local result
  src:complete({
    context = { bufnr = 0, cursor = { row = row, col = 0 }, cursor_before_line = lines[row] },
  }, function(r)
    result = r
  end)
  return result.items
end

local ddl = items({ "create table x (", "  id " }, 2)
check(#ddl > 10, "DDL icinde tipler")
local labels = {}
for _, item in ipairs(ddl) do
  labels[item.label] = true
end
check(labels["VARCHAR"], "statik yedekte VARCHAR")
check(labels["UUID"], "statik yedekte UUID")
check(labels["DEFAULT"], "DDL keyword DEFAULT")

local ddl_kinds = {}
for _, item in ipairs(ddl) do
  ddl_kinds[item.label] = item.kind
end
eq(ddl_kinds["DEFAULT"], 14, "DEFAULT keyword kind")

local dml = items({ "select  from t;" }, 1)
local dml_labels = {}
for _, item in ipairs(dml) do
  dml_labels[item.label] = true
end
check(dml_labels["SELECT"], "DB yokken keyword yedegi")

assist.setup()
check(registered.db_types, "db_types kayitli")
eq(vim.fn.exists(":DbTypesRefresh"), 2, "DbTypesRefresh komutu")

local triggers = {}
for _, sn in ipairs(snippets.sql or {}) do
  triggers[sn.trigger] = true
end
check(triggers.create, "create snippet")
check(triggers.createtable, "createtable snippet")

-- DB erisilemez: psql basarisiz olsa da statik tipler gelir
local proj = vim.fn.tempname()
vim.fn.mkdir(proj, "p")
vim.fn.writefile({ "<project/>" }, proj .. "/pom.xml")
vim.fn.writefile({ "DATABASE_URL=postgresql://u:p@127.0.0.1:1/db" }, proj .. "/.env.local")
local fake_bin = vim.fn.tempname()
vim.fn.mkdir(fake_bin, "p")
local fake = fake_bin .. "/psql"
local fh = assert(io.open(fake, "w"))
fh:write("#!/bin/sh\nexit 1\n")
fh:close()
vim.uv.fs_chmod(fake, 493)
local old_path = vim.env.PATH
vim.env.PATH = fake_bin .. ":" .. old_path
require("config.db.detect").invalidate()
local buf = vim.fn.bufadd(proj .. "/m.sql")
vim.fn.bufload(buf)
vim.bo[buf].filetype = "sql"
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "create table x (", "  id " })
local result
src:complete({
  context = { bufnr = buf, cursor = { row = 2, col = 0 }, cursor_before_line = "  id " },
}, function(r)
  result = r
end)
local failed_labels = {}
for _, item in ipairs(result.items) do
  failed_labels[item.label] = true
end
check(failed_labels["VARCHAR"], "psql basarisizken statik tip")
vim.wait(300)
vim.env.PATH = old_path
require("config.db.detect").invalidate()

io.write(("%d/%d passed\n"):format(total - failures, total))
if failures > 0 then
  os.exit(1)
end
