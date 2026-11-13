-- .env dosyalarından bağlantı tespiti.

local fs = require("config.db.fs")
local url = require("config.db.url")

local M = {}

local FILES = { ".env.local", ".env.development", ".env.dev", ".env" }
local URL_KEYS = { "DATABASE_URL", "DB_URL", "POSTGRES_URL", "MYSQL_URL" }

---@param value string
---@return string
local function resolve_placeholders(value)
  return (
    value
      :gsub("%${([%w_%.]+):([^}]*)}", function(name, default)
        local env = vim.env[name]
        if env and env ~= "" then
          return env
        end
        return default
      end)
      :gsub("%${([%w_%.]+)}", function(name)
        return vim.env[name] or ""
      end)
  )
end

---@param value string
---@return string
local function clean(value)
  value = vim.trim(value)
  value = value:match('^"(.*)"$') or value:match("^'(.*)'$") or value
  return resolve_placeholders(value)
end

---@param path string
---@param root string
---@return table<string, string>
local function parse_file(path, root)
  local props = {}
  local text = fs.read(path, root)
  if not text then
    return props
  end

  for line in text:gmatch("[^\r\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" then
      trimmed = trimmed:gsub("^export%s+", "")
      local key, value = trimmed:match("^([%w_%.%-]+)%s*=%s*(.-)%s*$")
      if key then
        props[key] = clean(value)
      end
    end
  end
  return props
end

---@param root string
---@return { file: string, props: table<string, string> }[]
local function files(root)
  local result = {}
  for _, name in ipairs(FILES) do
    local path = vim.fs.joinpath(root, name)
    local props = parse_file(path, root)
    if next(props) then
      result[#result + 1] = { file = name, props = props }
    end
  end
  return result
end

---@param name string
---@param root string
---@return string|nil
function M.lookup(name, root)
  for _, entry in ipairs(files(root)) do
    local value = entry.props[name]
    if value and value ~= "" then
      return value
    end
  end
  return nil
end

---@param root string
---@return table|nil
function M.detect(root)
  local entries = files(root)

  for _, entry in ipairs(entries) do
    for _, key in ipairs(URL_KEYS) do
      local value = entry.props[key]
      if value then
        local parsed = url.parse(value)
        if parsed then
          return { kind = parsed.kind, dsn = parsed.dsn, source = "dotenv:" .. entry.file }
        end
      end
    end
  end

  local source
  local props = {}
  for _, entry in ipairs(entries) do
    for key, value in pairs(entry.props) do
      if props[key] == nil then
        props[key] = value
        source = source or entry.file
      end
    end
  end

  local connection = props.DB_CONNECTION and props.DB_CONNECTION:lower() or nil
  local kind
  if connection == "pgsql" or connection == "postgres" or connection == "postgresql" then
    kind = "postgres"
  elseif connection == "mysql" or connection == "mariadb" then
    kind = "mysql"
  elseif connection == "sqlite" or connection == "sqlite3" then
    kind = "sqlite"
  elseif props.DB_HOST and (props.DB_DATABASE or props.DB_NAME) then
    kind = "postgres"
  end

  if kind == "sqlite" then
    local path = props.DB_DATABASE or props.DB_NAME or props.DATABASE_PATH or props.SQLITE_PATH
    local dsn = path and url.from_parts("sqlite", { path = path }) or nil
    if dsn then
      return { kind = "sqlite", dsn = dsn, source = "dotenv:" .. (source or ".env") }
    end
    return nil
  end

  if kind then
    local dsn = url.from_parts(kind, {
      host = props.DB_HOST or props.DB_SERVER,
      port = props.DB_PORT,
      user = props.DB_USER or props.DB_USERNAME,
      password = props.DB_PASSWORD,
      database = props.DB_DATABASE or props.DB_NAME,
    })
    if dsn then
      return { kind = kind, dsn = dsn, source = "dotenv:" .. (source or ".env") }
    end
  end

  return nil
end

return M
