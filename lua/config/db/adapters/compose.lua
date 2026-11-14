-- docker-compose / compose bağlantı adaptörü (best-effort).

local fs = require("config.db.fs")
local url = require("config.db.url")
local yaml = require("config.db.yaml")

local M = {}

---@param text string
---@return table<string, string>
local function list_environment(text)
  local props = {}
  for key, value in text:gmatch("%-%s*([%w_]+)=([^\r\n]+)") do
    props[key] = vim.trim(value:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1"))
  end
  return props
end

---@param text string
---@return table<string, string>
local function merged_environment(text, services)
  local props = {}
  if type(services) == "table" then
    for _, service in pairs(services) do
      local env = service and service.environment
      if type(env) == "table" then
        for key, value in pairs(env) do
          if type(value) == "string" then
            props[key] = value
          end
        end
      end
    end
  end
  for key, value in pairs(list_environment(text)) do
    props[key] = value
  end
  return props
end

---@param text string
---@return string|nil
local function published_port(text)
  local ports = text:match("ports:%s*(.-)\n%s*[%w_]+:%s*$") or text:match("ports:%s*(.-)$")
  local block = ports or text
  return block:match([[%-%s*"?([%d]+):[%d]+"?]])
end

---@param root string
---@return table|nil
function M.detect(root)
  local files = {}
  for _, pattern in ipairs({ root .. "/docker-compose*.yml", root .. "/compose*.yml" }) do
    vim.list_extend(files, vim.fn.glob(pattern, false, true))
  end
  table.sort(files)

  for _, path in ipairs(files) do
    local text = fs.read(path, root)
    if text then
      local parsed = yaml.parse(text) or {}
      local env = merged_environment(text, parsed.services)

      if env.DATABASE_URL and env.DATABASE_URL ~= "" then
        local parsed_url = url.parse(env.DATABASE_URL)
        if parsed_url then
          return {
            kind = parsed_url.kind,
            dsn = parsed_url.dsn,
            source = "compose:" .. vim.fs.relpath(root, path),
          }
        end
      end

      local port = published_port(text)
      if port then
        local kind, database, user, password
        if env.POSTGRES_DB then
          kind = "postgres"
          database = env.POSTGRES_DB
          user = env.POSTGRES_USER
          password = env.POSTGRES_PASSWORD
        elseif env.MYSQL_DATABASE then
          kind = "mysql"
          database = env.MYSQL_DATABASE
          user = env.MYSQL_USER
          password = env.MYSQL_PASSWORD
        end

        if kind and database then
          local dsn = url.from_parts(kind, {
            host = "localhost",
            port = port,
            user = user,
            password = password,
            database = database,
          })
          if dsn then
            return { kind = kind, dsn = dsn, source = "compose:" .. vim.fs.relpath(root, path) }
          end
        end
      end
    end
  end
  return nil
end

return M
