-- Unity projelerinde Roslyn'in "unused private member" uyarisini SADECE Unity
-- mesaj metotlari icin gizler.
--
-- Unity, Awake/Start/Update/OnCollisionEnter gibi metotlari reflection ile
-- cagirir; Roslyn bunu bilmedigi icin IDE0051 uretir. Kendi yazip kullanmadigin
-- private metotlar uyari vermeye devam eder. IDE0052 (kullanilmayan alan) da
-- oldugu gibi kalir.
--
-- Roslyn diagnostic'leri pull modeliyle (textDocument/diagnostic) gonderir;
-- bazi sunucular push (publishDiagnostics) kullanir. Ikisi de filtrelenir.
-- Kapsam: yalnizca Unity projesi (Assets/ + ProjectSettings/ProjectVersion.txt)
-- icindeki C# buffer'lari.

local M = {}

---@type table<string, true>|nil
local unity_message_names

---@return table<string, true>
local function message_names()
  if unity_message_names then
    return unity_message_names
  end

  unity_message_names = {}
  local ok, messages = pcall(require, "unitykit.messages")
  if ok then
    for _, kind in ipairs(messages.kinds) do
      for _, message in ipairs(messages.get(kind)) do
        unity_message_names[message.name] = true
      end
    end
  end

  return unity_message_names
end

---@param bufnr integer
---@return boolean
local function is_unity_project(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return false
  end

  local dir = vim.fs.dirname(name)
  for _ = 1, 64 do
    local has_assets = vim.fn.isdirectory(dir .. "/Assets") == 1
    local has_version = vim.fn.filereadable(dir .. "/ProjectSettings/ProjectVersion.txt") == 1
    if has_assets and has_version then
      return true
    end

    local parent = vim.fs.dirname(dir)
    if parent == dir then
      break
    end
    dir = parent
  end

  return false
end

---@param bufnr integer
---@param lnum integer 0-based line
---@return string|nil
local function method_name(bufnr, lnum)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
  if not line then
    return nil
  end

  return line:match("([%w_]+)%s*%(")
end

---@param code string|integer|table|nil
---@return string|nil
local function code_string(code)
  if type(code) == "table" then
    code = code.value
  end
  if type(code) == "string" then
    return code
  end
  return nil
end

---@param diagnostic table LSP diagnostic
---@param bufnr integer
---@return boolean
local function keep(diagnostic, bufnr)
  if code_string(diagnostic.code) ~= "IDE0051" then
    return true
  end

  local range = diagnostic.range
  local lnum = range and range.start and range.start.line
  if type(lnum) ~= "number" then
    return true
  end

  local name = method_name(bufnr, lnum)
  return not (name and message_names()[name])
end

---@param bufnr integer
---@return boolean
local function should_filter(bufnr)
  return vim.bo[bufnr].filetype == "cs" and is_unity_project(bufnr)
end

---@param diagnostics table[]
---@param bufnr integer
---@return table[]
local function filter(diagnostics, bufnr)
  return vim.tbl_filter(function(diagnostic)
    return keep(diagnostic, bufnr)
  end, diagnostics)
end

---@param diagnostics table[]|nil
---@param bufnr integer|nil
---@return table[]|nil
local function maybe_filter(diagnostics, bufnr)
  if type(diagnostics) ~= "table" or type(bufnr) ~= "number" then
    return diagnostics
  end
  if not vim.api.nvim_buf_is_valid(bufnr) or not should_filter(bufnr) then
    return diagnostics
  end
  return filter(diagnostics, bufnr)
end

function M.setup()
  local on_diagnostic = vim.lsp.diagnostic and vim.lsp.diagnostic.on_diagnostic
  local on_publish = vim.lsp.handlers and vim.lsp.handlers["textDocument/publishDiagnostics"]

  vim.lsp.config("roslyn_ls", {
    handlers = {
      -- Roslyn: pull diagnostics (textDocument/diagnostic)
      ["textDocument/diagnostic"] = function(err, result, ctx)
        if result and ctx then
          if result.kind == "full" then
            result.items = maybe_filter(result.items, ctx.bufnr)
          end
          for _, related in pairs(result.relatedDocuments or {}) do
            if related.kind == "full" then
              related.items = maybe_filter(related.items, ctx.bufnr)
            end
          end
        end
        if on_diagnostic then
          return on_diagnostic(err, result, ctx)
        end
      end,

      -- Diger sunucular: push diagnostics
      ["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
        if result then
          result.diagnostics = maybe_filter(result.diagnostics, ctx and ctx.bufnr)
        end
        if on_publish then
          return on_publish(err, result, ctx, config)
        end
        if result and result.diagnostics then
          vim.diagnostic.set(ctx.namespace, ctx.bufnr, result.diagnostics)
        end
      end,
    },
  })
end

return M
