-- SQL snippet'leri + PostgreSQL katalog tabanli tip completion'lari.
--
-- Tip listesi elle tutulmaz: ilk istekte `psql` ile canli veritabanindan
-- pg_type + format_type() okunur. PostgreSQL yukseltildiginde yeni tipler
-- otomatik gelir. Tablo/kolon/fonksiyon completion'lari postgres-language-server
-- (postgres_lsp) tarafindan DB semasindan saglanir; onun DDL tip tamamlamasi
-- olmadigi icin tipler buradan gelir.
--
-- Not: cmp_luasnip, snippet trigger'ini cmp item'inin `label` alani olarak
-- kullaniyor. Trigger tablo olursa label tablo olur ve nvim-cmp coker
-- (str.trim -> bad argument). Her trigger ayri string snippet olmali.

local M = {}

-- Kanonik isimlerin yaninda yaygin SQL takma adlari (format_type "character
-- varying" der; kullanicilar VARCHAR yazar). Yeni tipler bu listeye ihtiyac
-- duymaz, katalogdan otomatik gelir.
local aliases = {
  ["CHARACTER VARYING"] = { "VARCHAR", "VARCHAR(255)" },
  ["CHARACTER"] = { "CHAR", "CHAR(1)" },
  ["NUMERIC"] = { "DECIMAL", "NUMERIC(10,2)", "DECIMAL(10,2)" },
  ["INTEGER"] = { "INT" },
  ["BOOLEAN"] = { "BOOL" },
  ["TIMESTAMP WITH TIME ZONE"] = { "TIMESTAMPTZ" },
  ["TIME WITH TIME ZONE"] = { "TIMETZ" },
}

-- DB baglantisi yoksa kullanilan yedek liste. Baglanti varsa bu liste
-- kullanilmaz; tipler canli pg_type katalogundan gelir.
local fallback_types = {
  "BIGINT",
  "BIGSERIAL",
  "BIT",
  "BOOLEAN",
  "BOOL",
  "BYTEA",
  "CHAR",
  "CHAR(1)",
  "CHARACTER",
  "CHARACTER VARYING",
  "CIDR",
  "DATE",
  "DECIMAL",
  "DECIMAL(10,2)",
  "DOUBLE PRECISION",
  "INET",
  "INT",
  "INTEGER",
  "INTERVAL",
  "JSON",
  "JSONB",
  "MACADDR",
  "MONEY",
  "NUMERIC",
  "NUMERIC(10,2)",
  "REAL",
  "SERIAL",
  "SMALLINT",
  "SMALLSERIAL",
  "TEXT",
  "TIME",
  "TIMESTAMP",
  "TIMESTAMPTZ",
  "TIMESTAMP WITH TIME ZONE",
  "UUID",
  "VARCHAR",
  "VARCHAR(50)",
  "VARCHAR(100)",
  "VARCHAR(255)",
  "XML",
}

local TYPE_QUERY = [[
select distinct upper(format_type(t.oid, null)) as name
from pg_type t
join pg_namespace n on n.oid = t.typnamespace
where t.typtype in ('b', 'e', 'd', 'r', 'm')
  and t.typelem = 0
  and t.typtype <> 'c'
  and t.typisdefined
  and n.nspname <> 'information_schema'
  and t.typname not like '\_%'
order by 1;
]]

---@type table<string, { loading: boolean, at: integer?, types: string[]? }>
local cache = {}

local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

---@param dsn string
---@return string[]
local function type_names(dsn)
  local entry = cache[dsn]
  if not entry then
    entry = { loading = true }
    cache[dsn] = entry

    vim.system({ "psql", dsn, "-At", "-v", "ON_ERROR_STOP=1", "-c", TYPE_QUERY }, { text = true }, function(res)
      entry.loading = false
      entry.at = os.time()
      if res.code ~= 0 or not res.stdout then
        return
      end

      local names, seen = {}, {}
      for line in res.stdout:gmatch("[^\r\n]+") do
        local name = line:match("^(.-)%s*$")
        if name and name ~= "" and not seen[name] then
          seen[name] = true
          names[#names + 1] = name
          for _, alias in ipairs(aliases[name] or {}) do
            if not seen[alias] then
              seen[alias] = true
              names[#names + 1] = alias
            end
          end
        end
      end
      entry.types = names
    end)
  elseif not entry.loading and entry.types == nil and (os.time() - (entry.at or 0)) > 30 then
    -- Onceki deneme basarisiz: 30 sn sonra yeniden dene.
    cache[dsn] = nil
    return type_names(dsn)
  end

  return entry.types or {}
end

local function inside_greenfield_ddl(context)
  local lines = vim.api.nvim_buf_get_lines(context.bufnr, 0, context.cursor.row - 1, false)
  lines[#lines + 1] = context.cursor_before_line
  local text = table.concat(lines, "\n"):lower()

  local create = text:match("create%s+table[^;]*$")
  if create then
    local depth = 0
    for ch in create:gmatch("[()]") do
      depth = depth + (ch == "(" and 1 or -1)
    end
    if depth > 0 then
      return true
    end
  end

  return text:match("alter%s+table[^;]*add%s+column[^;]*$") ~= nil
end

function source:complete(params, callback)
  local context = params.context
  local bufnr = context.bufnr
  if vim.bo[bufnr].filetype ~= "sql" or not inside_greenfield_ddl(context) then
    callback({ items = {}, isIncomplete = false })
    return
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  local root = vim.fs.root(bufnr, { "postgres-language-server.jsonc", ".git" }) or vim.fs.dirname(name)
  local dsn = require("config.pg_env").database_url(root)
  local names
  if dsn then
    names = type_names(dsn)
  else
    names = fallback_types
    if not M.warned then
      M.warned = true
      vim.notify(
        "SQL: PostgreSQL baglantisi yok (DATABASE_URL / .env). Sabit tip listesi kullaniliyor.",
        vim.log.levels.INFO
      )
    end
  end

  local kinds = require("cmp.types").lsp.CompletionItemKind
  local items = {}
  for _, label in ipairs(names) do
    items[#items + 1] = { label = label, kind = kinds.TypeParameter }
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
  require("cmp").register_source("pg_types", source.new())
  snippet_setup()

  -- SQL buffer acilir acilmaz tip listesini onbellege al: ilk popup'ta hazir olsun.
  local function prefetch(buf)
    local name = vim.api.nvim_buf_get_name(buf)
    local root = vim.fs.root(buf, { "postgres-language-server.jsonc", ".git" }) or vim.fs.dirname(name)
    local dsn = require("config.pg_env").database_url(root)
    if dsn then
      type_names(dsn)
    end
  end

  local group = vim.api.nvim_create_augroup("SqlPgTypesPrefetch", { clear = true })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufEnter" }, {
    group = group,
    pattern = "*.sql",
    callback = function(ev)
      prefetch(ev.buf)
    end,
  })

  -- setup InsertEnter'da calisir; o an acik SQL buffer'i icin event gecmistir.
  local current = vim.api.nvim_get_current_buf()
  if vim.bo[current].filetype == "sql" then
    prefetch(current)
  end

  vim.api.nvim_create_user_command("PgTypesRefresh", function()
    cache = {}
    vim.notify("PostgreSQL tip onerileri yenilenecek", vim.log.levels.INFO)
  end, { desc = "SQL tip onerileri onbellegini temizle" })
end

-- Test/ileri kullanim icin kaynak sinifi
M.source = source

return M
