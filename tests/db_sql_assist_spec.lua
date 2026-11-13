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
package.loaded["cmp.types"] = { lsp = { CompletionItemKind = { TypeParameter = 25 } } }
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

eq(#items({ "select  from t;" }, 1), 0, "DDL disinda bos")

assist.setup()
check(registered.db_types, "db_types kayitli")
eq(vim.fn.exists(":DbTypesRefresh"), 2, "DbTypesRefresh komutu")

local triggers = {}
for _, sn in ipairs(snippets.sql or {}) do
  triggers[sn.trigger] = true
end
check(triggers.create, "create snippet")
check(triggers.createtable, "createtable snippet")

io.write(("%d/%d passed\n"):format(total - failures, total))
if failures > 0 then
  os.exit(1)
end
