-- Proje kökü tespiti (dil/framework bağımsız işaretler).

local M = {}

M.markers = {
  ".git",
  "package.json",
  "pom.xml",
  "build.gradle",
  "build.gradle.kts",
  "settings.gradle",
  "settings.gradle.kts",
  "Gemfile",
  "manage.py",
  "composer.json",
  "go.mod",
  "mix.exs",
  "Cargo.toml",
  "postgres-language-server.jsonc",
}

---@param bufnr integer
---@return string|nil
function M.root(bufnr)
  local found = vim.fs.root(bufnr, M.markers)
  if found then
    return vim.fs.normalize(found)
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return nil
  end
  return vim.fs.dirname(vim.fs.normalize(name))
end

return M
