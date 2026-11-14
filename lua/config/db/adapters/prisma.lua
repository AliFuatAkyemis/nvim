-- Prisma schema.prisma adaptörü.

local dotenv = require("config.db.adapters.dotenv")
local fs = require("config.db.fs")
local url = require("config.db.url")

local M = {}

local PROVIDERS = {
  postgresql = "postgres",
  postgres = "postgres",
  mysql = "mysql",
  sqlite = "sqlite",
}

---@param block string
---@param key string
---@return string|nil
local function field(block, key)
  return block:match(key .. '%s*=%s*"([^"]*)"') or block:match(key .. "%s*=%s*([^%s]+)")
end

---@param root string
---@return table|nil
function M.detect(root)
  local path = vim.fs.joinpath(root, "prisma", "schema.prisma")
  local text = fs.read(path, root)
  if not text then
    return nil
  end

  local block = text:match("datasource%s+%w+%s*(%b{})")
  if not block then
    return nil
  end

  local provider = field(block, "provider")
  local kind = provider and PROVIDERS[provider:lower()] or nil
  if not kind then
    return nil
  end

  local raw = field(block, "url")
  if not raw then
    return nil
  end

  local env_name = raw:match('^env%(%s*"([^"]+)"%s*%)$')
  if env_name then
    raw = dotenv.lookup(env_name, root) or vim.env[env_name]
  end
  if not raw or raw == "" then
    return nil
  end

  local parsed = url.parse(raw)
  if not parsed then
    return nil
  end

  local dsn = parsed.dsn
  if kind == "sqlite" then
    local relative = dsn:gsub("^sqlite://", "")
    if relative:sub(1, 1) ~= "/" then
      dsn = url.from_parts("sqlite", { path = vim.fs.normalize(vim.fs.joinpath(root, "prisma", relative)) })
    end
  end

  return { kind = kind, dsn = dsn, source = "prisma:prisma/schema.prisma" }
end

return M
