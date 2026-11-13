-- LSP entegrasyon yardımcıları: pgls env, sqls bağlantısı, syntax override.

local url = require("config.db.url")

local M = {}

---@param conn table|nil
---@param base table
---@return table
function M.pgls_env(conn, base)
  local env = vim.deepcopy(base or {})
  if conn and conn.kind == "postgres" then
    env.DATABASE_URL = conn.dsn
  end
  return env
end

---@param conn table|nil
---@return table|nil
function M.sqls_connection(conn)
  if not conn then
    return nil
  end
  if conn.kind == "mysql" then
    local dsn = url.to_go_mysql(conn.dsn)
    if dsn then
      return { driver = "mysql", dataSourceName = dsn }
    end
  elseif conn.kind == "sqlite" then
    local path = url.sqlite_path(conn.dsn, conn.root)
    if path then
      return { driver = "sqlite3", dataSourceName = path }
    end
  end
  return nil
end

---@param kind string|nil
---@return string|nil
function M.override(kind)
  if kind == "postgres" then
    return "postgres"
  end
  if kind == "mysql" then
    return "mysql"
  end
  return nil
end

return M
