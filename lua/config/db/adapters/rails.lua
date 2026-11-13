-- Rails config/database.yml adaptörü.

local fs = require("config.db.fs")
local url = require("config.db.url")
local yaml = require("config.db.yaml")

local M = {}

local ADAPTERS = {
  postgresql = "postgres",
  postgres = "postgres",
  mysql2 = "mysql",
  mysql = "mysql",
  trilogy = "mysql",
  sqlite3 = "sqlite",
}

---@param value any
---@return boolean
local function has_erb(value)
  return type(value) == "string" and value:find("<%%", 1, false) ~= nil
end

---@param props table
---@return table|nil
local function from_props(props)
  if has_erb(props.url) or has_erb(props.database) or has_erb(props.host) then
    return nil
  end

  if props.url then
    return url.parse(props.url)
  end

  local kind = ADAPTERS[props.adapter]
  if not kind then
    return nil
  end

  if kind == "sqlite" then
    local path = props.database
    if not path then
      return nil
    end
    return { kind = "sqlite", dsn = url.from_parts("sqlite", { path = path }) }
  end

  local dsn = url.from_parts(kind, {
    host = props.host or "localhost",
    port = props.port,
    user = props.username,
    password = props.password,
    database = props.database,
  })
  if not dsn then
    return nil
  end
  return { kind = kind, dsn = dsn }
end

---@param root string
---@return table|nil
function M.detect(root)
  local path = vim.fs.joinpath(root, "config", "database.yml")
  local text = fs.read(path, root)
  if not text then
    return nil
  end

  local parsed = yaml.parse(text) or {}
  local props = parsed.development
  if type(props) ~= "table" then
    for _, value in pairs(parsed) do
      if type(value) == "table" then
        props = value
        break
      end
    end
  end
  if not props then
    return nil
  end

  local conn = from_props(props)
  if not conn then
    return nil
  end
  if conn.kind == "sqlite" then
    local relative = conn.dsn:gsub("^sqlite://", "")
    if relative:sub(1, 1) ~= "/" then
      conn.dsn = url.from_parts("sqlite", { path = vim.fs.joinpath(root, relative) })
    end
  end
  return { kind = conn.kind, dsn = conn.dsn, source = "rails:config/database.yml" }
end

return M
