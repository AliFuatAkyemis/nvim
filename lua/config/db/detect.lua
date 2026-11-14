-- Bağlantı tespiti çekirdeği: proje kökü + adaptör sırası + cache + komutlar.

local adapters = require("config.db.adapters.init")
local project = require("config.db.project")
local url = require("config.db.url")

local M = {}

---@type table<string, table>
local cache = {}

---@param bufnr integer
---@return table|nil
function M.connection(bufnr)
  local root = project.root(bufnr)
  if not root then
    return nil
  end
  return M.connection_for_root(root)
end

---@param root string|nil
---@return table|nil
function M.connection_for_root(root)
  if not root then
    return nil
  end

  local cached = cache[root]
  if cached ~= nil then
    return cached == false and nil or cached
  end

  local conn = adapters.run(root)
  if not conn then
    cache[root] = false
    return nil
  end

  conn.root = root
  cache[root] = conn
  return conn
end

---@param bufnr integer
---@return string|nil
function M.kind(bufnr)
  local conn = M.connection(bufnr)
  return conn and conn.kind or nil
end

function M.invalidate()
  cache = {}
end

---@param bufnr integer
---@return string|nil
local function type_source(bufnr)
  local conn = M.connection(bufnr)
  if not conn then
    return "static fallback (PG)"
  end
  if conn.kind == "postgres" and vim.fn.executable("psql") == 1 then
    return "live pg_type catalog"
  end
  return "static fallback (" .. conn.kind .. ")"
end

local function info()
  local bufnr = vim.api.nvim_get_current_buf()
  local conn = M.connection(bufnr)
  local lines = {}

  if not conn then
    lines[#lines + 1] = "SQL DB: no connection found"
    lines[#lines + 1] = "Type source: " .. type_source(bufnr)
    lines[#lines + 1] = "LSP: none (snippets + static types)"
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    return
  end

  local clients = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    clients[#clients + 1] = client.name
  end

  lines[#lines + 1] = "SQL DB: " .. conn.kind
  lines[#lines + 1] = "Source: " .. conn.source
  lines[#lines + 1] = "Root: " .. conn.root
  lines[#lines + 1] = "DSN: " .. url.mask(conn.dsn)
  lines[#lines + 1] = "LSP: " .. (#clients > 0 and table.concat(clients, ", ") or "none")
  lines[#lines + 1] = "Type source: " .. type_source(bufnr)
  if conn.kind == "postgres" then
    lines[#lines + 1] = "Note: pgls daemon captures env at first start; restart it after changing the DSN."
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

local function refresh()
  M.invalidate()
  for _, client in ipairs(vim.lsp.get_clients()) do
    if client.name == "postgres_lsp" or client.name == "sqls" then
      client:stop()
    end
  end
  vim.defer_fn(function()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local ft = vim.bo[bufnr].filetype
      if (ft == "sql" or ft == "mysql") and vim.api.nvim_buf_is_loaded(bufnr) then
        vim.b[bufnr].sql_type_override = nil
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd("doautocmd FileType " .. ft)
        end)
      end
    end
    vim.notify("DB detection refreshed", vim.log.levels.INFO)
  end, 200)
end

function M.setup()
  vim.api.nvim_create_user_command("DbDetectInfo", info, { desc = "SQL DB detection info" })
  vim.api.nvim_create_user_command("DbDetectRefresh", refresh, { desc = "Refresh SQL DB detection" })
end

return M
