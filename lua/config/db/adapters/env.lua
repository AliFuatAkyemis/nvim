-- Ortam değişkenlerinden bağlantı tespiti.

local url = require("config.db.url")

local M = {}

local URL_KEYS = { "DATABASE_URL", "DB_URL", "POSTGRES_URL", "MYSQL_URL" }

---@param key string
---@return string|nil
local function env(key)
  local value = vim.env[key]
  if value and value ~= "" then
    return value
  end
  return nil
end

---@param input string
---@param source string
---@return table|nil
local function connection(input, source)
  local parsed = url.parse(input)
  if not parsed then
    return nil
  end
  return { kind = parsed.kind, dsn = parsed.dsn, source = source }
end

---@return table|nil
local function from_parts()
  local pg_host = env("PGHOST")
  local pg_database = env("PGDATABASE")
  if pg_host and pg_database then
    local dsn = url.from_parts("postgres", {
      host = pg_host,
      port = env("PGPORT"),
      user = env("PGUSER") or vim.env.USER,
      password = env("PGPASSWORD"),
      database = pg_database,
    })
    if dsn then
      return { kind = "postgres", dsn = dsn, source = "env:PG*" }
    end
  end

  local mysql_host = env("MYSQL_HOST")
  local mysql_database = env("MYSQL_DATABASE")
  if mysql_host and mysql_database then
    local dsn = url.from_parts("mysql", {
      host = mysql_host,
      port = env("MYSQL_PORT") or "3306",
      user = env("MYSQL_USER"),
      password = env("MYSQL_PASSWORD"),
      database = mysql_database,
    })
    if dsn then
      return { kind = "mysql", dsn = dsn, source = "env:MYSQL_*" }
    end
  end

  local sqlite_path = env("DATABASE_PATH") or env("SQLITE_PATH")
  if sqlite_path then
    local dsn = url.from_parts("sqlite", { path = sqlite_path })
    if dsn then
      return { kind = "sqlite", dsn = dsn, source = "env:DATABASE_PATH" }
    end
  end

  return nil
end

---@param _ string
---@return table|nil
function M.detect(_)
  for _, key in ipairs(URL_KEYS) do
    local value = env(key)
    if value then
      local conn = connection(value, "env:" .. key)
      if conn then
        return conn
      end
    end
  end
  return from_parts()
end

return M
