-- Dialekt bazlı tip listeleri.
-- PostgreSQL'de listeler canlı katalogdan gelir; buradakiler yedek/statik.

local M = {}

local postgres_static = {
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

local mysql_static = {
  "BIGINT",
  "BINARY",
  "BIT",
  "BLOB",
  "BOOLEAN",
  "CHAR",
  "CHAR(1)",
  "DATE",
  "DATETIME",
  "DECIMAL",
  "DECIMAL(10,2)",
  "DOUBLE",
  "ENUM",
  "FLOAT",
  "INT",
  "INTEGER",
  "JSON",
  "LONGBLOB",
  "LONGTEXT",
  "MEDIUMBLOB",
  "MEDIUMINT",
  "MEDIUMTEXT",
  "NUMERIC",
  "NUMERIC(10,2)",
  "SMALLINT",
  "TEXT",
  "TIME",
  "TIMESTAMP",
  "TINYBLOB",
  "TINYINT",
  "TINYTEXT",
  "VARBINARY",
  "VARCHAR",
  "VARCHAR(50)",
  "VARCHAR(100)",
  "VARCHAR(255)",
  "YEAR",
}

local sqlite_static = {
  "BLOB",
  "BOOLEAN",
  "DATE",
  "DATETIME",
  "DECIMAL",
  "DOUBLE",
  "FLOAT",
  "INTEGER",
  "NUMERIC",
  "REAL",
  "TEXT",
  "VARCHAR(255)",
}

M.alias_map = {
  ["CHARACTER VARYING"] = { "VARCHAR", "VARCHAR(255)" },
  ["CHARACTER"] = { "CHAR", "CHAR(1)" },
  ["NUMERIC"] = { "DECIMAL", "NUMERIC(10,2)", "DECIMAL(10,2)" },
  ["INTEGER"] = { "INT" },
  ["BOOLEAN"] = { "BOOL" },
  ["TIMESTAMP WITH TIME ZONE"] = { "TIMESTAMPTZ" },
  ["TIME WITH TIME ZONE"] = { "TIMETZ" },
}

M.postgres_query = [[
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

---@param kind string|nil
---@return string[]
function M.static(kind)
  if kind == "mysql" then
    return vim.deepcopy(mysql_static)
  end
  if kind == "sqlite" then
    return vim.deepcopy(sqlite_static)
  end
  return vim.deepcopy(postgres_static)
end

---@param raw string[]
---@param kind string
---@return string[]
function M.normalize(raw, kind)
  local out = {}
  local seen = {}
  local function add(name)
    if name and name ~= "" and not seen[name] then
      seen[name] = true
      out[#out + 1] = name
    end
  end

  for _, line in ipairs(raw or {}) do
    local name = line:match("^(.-)%s*$")
    if name and name ~= "" then
      name = name:upper()
      add(name)
      if kind == "postgres" then
        for _, alias in ipairs(M.alias_map[name] or {}) do
          add(alias)
        end
      end
    end
  end

  if #out == 0 then
    return M.static(kind)
  end
  return out
end

return M
