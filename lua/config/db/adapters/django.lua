-- Django settings.py adaptörü.

local fs = require("config.db.fs")
local url = require("config.db.url")

local M = {}

local ENGINES = {
  ["django.db.backends.postgresql"] = "postgres",
  ["django.db.backends.postgresql_psycopg2"] = "postgres",
  ["django.db.backends.mysql"] = "mysql",
  ["django.db.backends.sqlite3"] = "sqlite",
}

---@param root string
---@return string[]
local function settings_files(root)
  local files = {}
  for _, path in ipairs({ vim.fs.joinpath(root, "settings.py") }) do
    if vim.uv.fs_stat(path) then
      files[#files + 1] = path
    end
  end
  for _, pattern in ipairs({ root .. "/*/settings.py", root .. "/*/settings/*.py" }) do
    for _, path in ipairs(vim.fn.glob(pattern, false, true)) do
      files[#files + 1] = path
    end
  end
  return files
end

---@param text string
---@return string|nil
local function database_url(text)
  return text:match("DATABASE_URL%s*=%s*[\"']([^\"']+)[\"']")
end

---@param text string
---@param key string
---@return string|nil
local function field(text, key)
  return text:match("[\"']" .. key .. "[\"']%s*:%s*[\"']([^\"']*)[\"']")
end

---@param text string
---@return string|nil
local function default_block(text)
  local start = text:find("DATABASES%s*=%s*{")
  if not start then
    return nil
  end
  local block_start = text:find("[\"']default[\"']%s*:%s*{", start)
  if not block_start then
    return nil
  end
  local brace = text:find("{", block_start)
  if not brace then
    return nil
  end
  return text:sub(brace):match("^(%b{})")
end

---@param root string
---@param text string
---@return table|nil
local function from_databases(root, text)
  local block = default_block(text)
  if not block then
    return nil
  end

  local engine = field(block, "ENGINE")
  local kind = engine and ENGINES[engine] or nil
  if not kind then
    return nil
  end

  local name = field(block, "NAME")
  local base_relative = block:match("[\"']NAME[\"']%s*:%s*BASE_DIR%s*/%s*[\"']([^\"']+)[\"']")
  if not name then
    name = base_relative
  end
  if not name then
    return nil
  end

  if kind == "sqlite" then
    local path = base_relative and vim.fs.joinpath(root, base_relative) or name
    return { kind = "sqlite", dsn = url.from_parts("sqlite", { path = vim.fs.normalize(path) }) }
  end

  return {
    kind = kind,
    dsn = url.from_parts(kind, {
      host = field(block, "HOST") or "localhost",
      port = field(block, "PORT"),
      user = field(block, "USER"),
      password = field(block, "PASSWORD"),
      database = name,
    }),
  }
end

---@param root string
---@return table|nil
function M.detect(root)
  for _, path in ipairs(settings_files(root)) do
    local text = fs.read(path, root)
    if text then
      local raw = database_url(text)
      if raw then
        local parsed = url.parse(raw)
        if parsed then
          return { kind = parsed.kind, dsn = parsed.dsn, source = "django:" .. vim.fs.relpath(root, path) }
        end
      end

      local conn = from_databases(root, text)
      if conn and conn.dsn then
        return { kind = conn.kind, dsn = conn.dsn, source = "django:" .. vim.fs.relpath(root, path) }
      end
    end
  end
  return nil
end

return M
