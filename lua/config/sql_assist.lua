-- SQL snippet'leri + cmp "db_types" tip kaynağı.
--
-- PostgreSQL tipleri canlı pg_type kataloğundan (psql) gelir; MySQL/SQLite
-- statik listelerden. Bağlantı yoksa varsayılan PostgreSQL listesi kullanılır.
-- Tip kaynağı yalnızca DDL bağlamında çalışır.

local detect = require("config.db.detect")
local types = require("config.db.types")
local url = require("config.db.url")

local M = {}

M.warned = false

---@type table<string, { loading: boolean, at: integer?, names: string[]? }>
local cache = {}

---@param lines string[]
---@return boolean
local function inside_create_table(lines)
  local text = table.concat(lines, "\n"):lower()
  local stmt = text:match("create%s+table[^;]*$")
  if not stmt then
    return false
  end
  local depth = 0
  for ch in stmt:gmatch("[()]") do
    depth = depth + (ch == "(" and 1 or -1)
  end
  return depth > 0
end

---@param lines string[]
---@return boolean
local function after_add_column(lines)
  local text = table.concat(lines, "\n"):lower()
  return text:match("alter%s+table[^;]*add%s+column[^;]*$") ~= nil
end

---@param context table
---@return boolean
local function in_ddl(context)
  local lines = vim.api.nvim_buf_get_lines(context.bufnr, 0, context.cursor.row - 1, false)
  lines[#lines + 1] = context.cursor_before_line
  return inside_create_table(lines) or after_add_column(lines)
end

---@param dsn string
---@return string[]
local function postgres_types(dsn)
  local entry = cache[dsn]
  if not entry then
    entry = { loading = true }
    cache[dsn] = entry

    local sanitized, password = url.without_password(dsn)
    local env = vim.fn.environ()
    if password then
      env.PGPASSWORD = password
    end

    vim.system(
      { "psql", "-w", sanitized, "-At", "-v", "ON_ERROR_STOP=1", "-c", types.postgres_query },
      { text = true, timeout = 5000, env = env },
      function(res)
        entry.loading = false
        entry.at = os.time()
        if res.code == 0 and res.stdout then
          local raw = vim.split(res.stdout, "\n", { trimempty = true })
          entry.names = types.normalize(raw, "postgres")
        end
      end
    )
  elseif not entry.loading and entry.names == nil and (os.time() - (entry.at or 0)) > 30 then
    cache[dsn] = nil
    return postgres_types(dsn)
  end

  return entry.names or {}
end

local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:complete(params, callback)
  local context = params.context
  local bufnr = context.bufnr
  if vim.bo[bufnr].filetype ~= "sql" then
    callback({ items = {}, isIncomplete = false })
    return
  end

  local ddl = in_ddl(context)
  local conn = detect.connection(bufnr)
  if not ddl and conn then
    -- Bağlantı varsa keyword/schema önerileri pgls'ten gelir.
    callback({ items = {}, isIncomplete = false })
    return
  end

  local kinds = require("cmp.types").lsp.CompletionItemKind
  local items = {}
  local seen = {}

  ---@param label string
  ---@param kind integer
  local function add(label, kind)
    if not seen[label] then
      seen[label] = true
      items[#items + 1] = { label = label, kind = kind }
    end
  end

  if ddl then
    local names
    if conn and conn.kind == "postgres" and vim.fn.executable("psql") == 1 then
      names = postgres_types(conn.dsn)
      if #names == 0 then
        names = types.static("postgres")
      end
    else
      names = types.static(conn and conn.kind or nil)
    end
    for _, label in ipairs(names) do
      add(label, kinds.TypeParameter)
    end
    for _, label in ipairs(types.ddl_keywords) do
      add(label, kinds.Keyword)
    end
  end

  if not conn then
    for _, label in ipairs(types.keywords) do
      add(label, kinds.Keyword)
    end
    if not M.warned then
      M.warned = true
      vim.notify("SQL: no DB connection, using static type/keyword list.", vim.log.levels.INFO)
    end
  end

  callback({ items = items, isIncomplete = false })
end

local function snippet_setup()
  local ls = require("luasnip")
  local s = ls.snippet
  local t = ls.text_node
  local i = ls.insert_node

  ---@return table
  local function create_table_body()
    return {
      t("CREATE TABLE "),
      i(1, "table_name"),
      t(" ("),
      i(2),
      t(");"),
      i(0),
    }
  end

  ls.add_snippets("sql", {
    s({ trig = "create", dscr = "CREATE TABLE" }, create_table_body()),
    s({ trig = "createtable", dscr = "CREATE TABLE" }, create_table_body()),
  })
end

function M.setup()
  require("cmp").register_source("db_types", source.new())
  snippet_setup()

  vim.api.nvim_create_user_command("DbTypesRefresh", function()
    cache = {}
    vim.notify("Refreshing SQL type cache", vim.log.levels.INFO)
  end, { desc = "Clear SQL type cache" })

  -- Dosya açılışında PG tip listesini önceden ısıt.
  local function prefetch(bufnr)
    if vim.bo[bufnr].filetype ~= "sql" or vim.fn.executable("psql") ~= 1 then
      return
    end
    local conn = detect.connection(bufnr)
    if conn and conn.kind == "postgres" then
      postgres_types(conn.dsn)
    end
  end

  local group = vim.api.nvim_create_augroup("SqlTypesPrefetch", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "sql",
    callback = function(ev)
      prefetch(ev.buf)
    end,
  })
  prefetch(vim.api.nvim_get_current_buf())
end

-- Test/ileri kullanim icin kaynak sinifi
M.source = source

return M
