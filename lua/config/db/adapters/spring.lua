-- Spring Boot application.properties/yml datasource adaptörü.

local dotenv = require("config.db.adapters.dotenv")
local fs = require("config.db.fs")
local url = require("config.db.url")
local yaml = require("config.db.yaml")

local M = {}

---@param value string
---@param root string|nil
---@return string
local function resolve(value, root)
  return (
    value
      :gsub("%${([%w_%.]+):([^}]*)}", function(name, default)
        local env = vim.env[name]
        if env and env ~= "" then
          return env
        end
        if root then
          local found = dotenv.lookup(name, root)
          if found then
            return found
          end
        end
        return default
      end)
      :gsub("%${([%w_%.]+)}", function(name)
        local env = vim.env[name]
        if env and env ~= "" then
          return env
        end
        if root then
          return dotenv.lookup(name, root) or ""
        end
        return ""
      end)
  )
end

---@param value string
---@param root string|nil
---@return string
local function clean(value, root)
  value = value:gsub("%s+#.*$", "")
  value = value:match('^"(.*)"$') or value:match("^'(.*)'$") or value
  return resolve(vim.trim(value), root)
end

---@param path string
---@param root string|nil
---@return table<string, string>
function M.read_properties(path, root)
  local props = {}
  local text = fs.read(path, root or vim.fs.dirname(path))
  if not text then
    return props
  end
  for line in text:gmatch("[^\r\n]+") do
    local key, value = line:match("^%s*([%w_.%-]+)%s*[=:]%s*(.-)%s*$")
    if key then
      props[key] = clean(value, root)
    end
  end
  return props
end

---@param tbl table
---@param prefix string
---@param out table<string, string>
local function flatten(tbl, prefix, out)
  for key, value in pairs(tbl) do
    local full = prefix == "" and key or (prefix .. "." .. key)
    if type(value) == "table" then
      flatten(value, full, out)
    else
      out[full] = value
    end
  end
end

---@param path string
---@param root string
---@return table<string, string>
local function read_any(path, root)
  if path:match("%.properties$") then
    return M.read_properties(path, root)
  end
  local text = fs.read(path, root)
  if not text then
    return {}
  end
  local parsed = yaml.parse(text) or {}
  local flat = {}
  flatten(parsed, "", flat)
  for key, value in pairs(flat) do
    flat[key] = clean(value, root)
  end
  return flat
end

---@param dsn string
---@param username string|nil
---@param password string|nil
---@return string
local function with_credentials(dsn, username, password)
  if not username or username == "" or dsn:find("@", 1, true) then
    return dsn
  end
  local scheme, rest = dsn:match("^([%a][%w+.-]*://)(.*)$")
  if not scheme then
    return dsn
  end
  local credentials = username
  if password and password ~= "" then
    credentials = credentials .. ":" .. password
  end
  return scheme .. credentials .. "@" .. rest
end

---@param root string
---@return table|nil
function M.detect(root)
  local resources = vim.fs.joinpath(root, "src", "main", "resources")
  local candidates = {}
  for _, name in ipairs({ "application.properties", "application.yml", "application.yaml" }) do
    local path = vim.fs.joinpath(resources, name)
    if vim.uv.fs_stat(path) then
      candidates[#candidates + 1] = path
    end
  end
  local variants = vim.fn.glob(resources .. "/application-*.{properties,yml,yaml}", false, true)
  table.sort(variants)
  vim.list_extend(candidates, variants)

  for _, path in ipairs(candidates) do
    local props = read_any(path, root)
    local raw = props["spring.datasource.url"] or props["spring.datasource.hikari.jdbc-url"]
    if raw and raw ~= "" then
      local parsed = url.parse(raw)
      if parsed then
        local dsn =
          with_credentials(parsed.dsn, props["spring.datasource.username"], props["spring.datasource.password"])
        return {
          kind = parsed.kind,
          dsn = dsn,
          source = "spring:" .. vim.fs.relpath(root, path),
        }
      end
    end
  end
  return nil
end

return M
