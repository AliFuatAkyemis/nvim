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
    return "statik yedek (PG)"
  end
  if conn.kind == "postgres" and vim.fn.executable("psql") == 1 then
    return "canli pg_type katalogu"
  end
  return "statik yedek (" .. conn.kind .. ")"
end

local function info()
  local bufnr = vim.api.nvim_get_current_buf()
  local conn = M.connection(bufnr)
  local lines = {}

  if not conn then
    lines[#lines + 1] = "SQL DB: baglanti bulunamadi"
    lines[#lines + 1] = "Tip kaynagi: " .. type_source(bufnr)
    lines[#lines + 1] = "LSP: yok (snippet + statik tipler)"
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    return
  end

  local clients = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    clients[#clients + 1] = client.name
  end

  lines[#lines + 1] = "SQL DB: " .. conn.kind
  lines[#lines + 1] = "Kaynak: " .. conn.source
  lines[#lines + 1] = "Kok: " .. conn.root
  lines[#lines + 1] = "DSN: " .. url.mask(conn.dsn)
  lines[#lines + 1] = "LSP: " .. (#clients > 0 and table.concat(clients, ", ") or "yok")
  lines[#lines + 1] = "Tip kaynagi: " .. type_source(bufnr)
  if conn.kind == "postgres" then
    lines[#lines + 1] = "Not: pgls daemon env'i ilk acilista alir; DSN degistiyse daemon'i yeniden baslat."
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
      if ft == "sql" or ft == "mysql" then
        vim.b[bufnr].sql_type_override = nil
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd("doautocmd FileType " .. ft)
        end)
      end
    end
    vim.notify("DB tespiti yenilendi", vim.log.levels.INFO)
  end, 200)
end

function M.setup()
  vim.api.nvim_create_user_command("DbDetectInfo", info, { desc = "SQL DB tespit bilgisi" })
  vim.api.nvim_create_user_command("DbDetectRefresh", refresh, { desc = "SQL DB tespitini yenile" })
end

return M
