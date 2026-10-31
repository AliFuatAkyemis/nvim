-- lua/config/indent_sync.lua
-- Formatter config'i ile buffer indent ayarlarini hizalar.
--
-- Ilke: buffer indent ayarlari tek dogru kaynak. Kaydederken conform
-- argumanlarini bu ayarlardan uretir (bkz. plugins/conform.lua), boylece
-- yazarken gorunen girinti ile format sonrasi girinti ayni olur.
--
-- Oncelik: proje formatter config > .editorconfig (Neovim built-in) > global 4.
-- Hicbir hata disari sizmaz; cozumlenemeyen durumda mevcut ayar korunur.

local M = {}

local DEFAULT_WIDTH = 4

-- Cache: ft + dizin -> opts tablosu veya false (negatif cache)
local cache = {}
-- Cozumlenmis prettier config cache'i (node cagrisini tekrarlamamak icin).
local prettier_cache = {}
-- prettier config yolu cache'i (dizin bazli; subprocess tekrarlanmasin).
local prettier_path_cache = {}

local function clear_cache()
  cache = {}
  prettier_cache = {}
  prettier_path_cache = {}
end

local function positive(n)
  n = tonumber(n)
  if n and n > 0 then
    return math.floor(n)
  end
  return nil
end

local function make(width, tabstop, expandtab)
  width = positive(width)
  if not width then
    return nil
  end
  tabstop = positive(tabstop) or width
  return {
    shiftwidth = width,
    tabstop = tabstop,
    softtabstop = expandtab and width or -1,
    expandtab = expandtab ~= false,
  }
end

--- Global varsayilan: 4 bosluk.
function M.fallback_opts()
  return make(DEFAULT_WIDTH, DEFAULT_WIDTH, true)
end

--- clang-format --dump-config ciktisini cozumler.
---@param text string|nil
---@return table|nil
function M.parse_clang_dump(text)
  if type(text) ~= "string" or text == "" then
    return nil
  end
  -- Alan adlari ic ice gecebilir (ConstructorInitializerIndentWidth gibi);
  -- satir basina sabitleyerek yanlis eslesmeyi onle.
  local dump = "\n" .. text
  local width = dump:match("\nIndentWidth:%s*(%d+)")
  if not width then
    return nil
  end
  local tabstop = dump:match("\nTabWidth:%s*(%d+)")
  local use_tab = dump:match("\nUseTab:%s*(%a+)")
  local expandtab = (use_tab == nil) or (use_tab == "Never")
  return make(width, tabstop, expandtab)
end

--- Prettier config tablosunu cozumler.
---@param cfg table|nil
---@return table|nil
function M.parse_prettier(cfg)
  if type(cfg) ~= "table" then
    return nil
  end
  local width = positive(cfg.tabWidth) or 2 -- prettier varsayilani
  if type(cfg.tabWidth) == "number" and cfg.tabWidth <= 0 then
    width = 2
  end
  return make(width, width, cfg.useTabs ~= true)
end

--- stylua.toml icerigini cozumler.
---@param text string|nil
---@return table|nil
function M.parse_stylua(text)
  if type(text) ~= "string" or text == "" then
    return nil
  end
  local indent_type = text:match('indent_type%s*=%s*"([%a]+)"')
  local indent_width = text:match("indent_width%s*=%s*(%d+)")
  if not indent_type and not indent_width then
    return nil
  end
  local width = positive(indent_width) or DEFAULT_WIDTH
  return make(width, width, (indent_type or "Spaces") ~= "Tabs")
end

--- rustfmt.toml icerigini cozumler.
---@param text string|nil
---@return table|nil
function M.parse_rustfmt(text)
  if type(text) ~= "string" or text == "" then
    return nil
  end
  local tab_spaces = text:match("tab_spaces%s*=%s*(%d+)")
  local hard_tabs = text:match("hard_tabs%s*=%s*(%a+)")
  if not tab_spaces and not hard_tabs then
    return nil
  end
  local width = positive(tab_spaces) or DEFAULT_WIDTH
  return make(width, width, hard_tabs ~= "true")
end

-- ── Yardimcilar ─────────────────────────────────────────────────────────────

local function executable(name)
  local path = vim.fn.exepath(name)
  if path ~= "" then
    return path
  end
  local mason = vim.fn.stdpath("data") .. "/mason/bin/" .. name
  if vim.fn.executable(mason) == 1 then
    return mason
  end
  return nil
end

local function find_up(names, start)
  if not start or start == "" then
    return nil
  end
  local ok, found = pcall(vim.fs.find, names, { path = start, upward = true })
  if ok and found and found[1] then
    return found[1]
  end
  return nil
end

local function read_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines then
    return nil
  end
  return table.concat(lines, "\n")
end

--- Alt surec calistir; hata/timeout -> nil.
local function run(cmd, opts, timeout)
  local ok, proc = pcall(vim.system, cmd, opts or {})
  if not ok or not proc then
    return nil
  end
  local ok_wait, result = pcall(proc.wait, proc, timeout)
  if not ok_wait or not result or result.code ~= 0 then
    return nil
  end
  return result.stdout
end

local function dir_of(file)
  if file and file ~= "" then
    return vim.fs.dirname(file)
  end
  return vim.fn.getcwd()
end

-- ── Proje config kesfi (conform da kullanir) ─────────────────────────────────

function M.clang_config(dir)
  return find_up({ ".clang-format", "_clang-format" }, dir)
end

function M.stylua_config(dir)
  return find_up({ "stylua.toml", ".stylua.toml" }, dir)
end

function M.rustfmt_config(dir)
  return find_up({ "rustfmt.toml", ".rustfmt.toml" }, dir)
end

function M.prettier_config(file)
  if not file or file == "" then
    return nil
  end
  local dir = dir_of(file)
  local cached = prettier_path_cache[dir]
  if cached ~= nil then
    return cached or nil
  end
  local exe = executable("prettier")
  if not exe then
    prettier_path_cache[dir] = false
    return nil
  end
  local out = run({ exe, "--find-config-path", file }, { text = true }, 2000)
  if not out then
    prettier_path_cache[dir] = false
    return nil
  end
  out = vim.trim(out)
  if out == "" then
    prettier_path_cache[dir] = false
    return nil
  end
  -- prettier bazi surumlerde goreli yol dondurur; mutlak yola cevir.
  local path = vim.fn.fnamemodify(out, ":p")
  prettier_path_cache[dir] = path
  return path
end

--- JS/YAML prettier config icin node resolveConfig.
local function prettier_config_via_node(file)
  local node = executable("node") or executable("nodejs")
  local api = vim.fn.stdpath("data") .. "/mason/packages/prettier/node_modules/prettier/index.cjs"
  if not node or vim.fn.filereadable(api) == 0 then
    return nil
  end
  local script = "require("
    .. string.format("%q", api)
    .. ").resolveConfig(process.argv[1]).then(function(c){"
    .. 'process.stdout.write(c ? JSON.stringify(c) : "null")'
    .. '}).catch(function(){process.stdout.write("null")})'
  local out = run({ node, "-e", script, file }, { text = true }, 2000)
  if not out or out == "" or out == "null" then
    return nil
  end
  local ok, cfg = pcall(vim.json.decode, out)
  if ok and type(cfg) == "table" then
    -- resolveConfig bazi alanlari doldurmayabilir; varsayilan 2 zaten
    -- prettier'in kendi varsayilani.
    return cfg
  end
  return nil
end

local function prettier_config_table(exe, file, config_path)
  if not config_path then
    return nil
  end
  local lower = config_path:lower()
  if lower:match("%.json$") then
    local text = read_file(config_path)
    if text then
      local ok, parsed = pcall(vim.json.decode, text)
      if ok and type(parsed) == "table" then
        if vim.fs.basename(config_path) == "package.json" and type(parsed.prettier) == "table" then
          return parsed.prettier
        elseif type(parsed.prettier) ~= "table" then
          return parsed
        end
      end
    end
  end
  return prettier_config_via_node(file)
end

local function prettier_resolved(exe, file, config_path)
  if not config_path then
    return nil
  end
  local cached = prettier_cache[config_path]
  if cached ~= nil then
    return cached or nil
  end
  local cfg = prettier_config_table(exe, file, config_path)
  prettier_cache[config_path] = cfg or false
  return cfg
end

-- ── Cozumleyiciler ──────────────────────────────────────────────────────────

local function resolve_clang(file, dir)
  local cfg = M.clang_config(dir)
  local exe = executable("clang-format")
  if not cfg or not exe then
    return nil -- proje kurali yok: mevcut ayar korunur (global/editorconfig)
  end
  local cmd = { exe, "--style=file" }
  if file and file ~= "" then
    vim.list_extend(cmd, { "--assume-filename", file })
  end
  vim.list_extend(cmd, { "--dump-config" })
  local out = run(cmd, { text = true, cwd = dir }, 1000)
  return M.parse_clang_dump(out)
end

local function resolve_prettier(file)
  local exe = executable("prettier")
  if not exe then
    return nil
  end
  local path = M.prettier_config(file)
  if not path then
    return nil -- proje kurali yok: mevcut ayar korunur (global/editorconfig)
  end
  return M.parse_prettier(prettier_resolved(exe, file, path))
end

local function resolve_stylua(_, dir)
  local path = M.stylua_config(dir)
  if not path then
    return nil
  end
  return M.parse_stylua(read_file(path))
end

local function resolve_rustfmt(_, dir)
  local path = M.rustfmt_config(dir)
  if path then
    local opts = M.parse_rustfmt(read_file(path))
    if opts then
      return opts
    end
  end
  -- rustfmt config yoksa varsayilani: 4 bosluk. Buffer'i buna sabitle ki
  -- editorconfig farkli bir sey soylese bile yazim = format olsun.
  return M.fallback_opts()
end

local function resolve_go()
  -- gofmt standardi: tab, tabstop 4.
  return { shiftwidth = 4, tabstop = 4, softtabstop = -1, expandtab = false }
end

local RESOLVERS = {
  c = resolve_clang,
  cpp = resolve_clang,
  objc = resolve_clang,
  objcpp = resolve_clang,
  javascript = resolve_prettier,
  javascriptreact = resolve_prettier,
  typescript = resolve_prettier,
  typescriptreact = resolve_prettier,
  html = resolve_prettier,
  htmlangular = resolve_prettier,
  css = resolve_prettier,
  scss = resolve_prettier,
  less = resolve_prettier,
  json = resolve_prettier,
  jsonc = resolve_prettier,
  yaml = resolve_prettier,
  lua = resolve_stylua,
  rust = resolve_rustfmt,
  go = resolve_go,
}

local function resolve(bufnr, ft, file)
  local dir = dir_of(file)
  local key = ft .. "\0" .. dir
  local cached = cache[key]
  if cached ~= nil then
    return cached or nil
  end

  local resolver = RESOLVERS[ft]
  local ok, opts = pcall(resolver, file, dir)
  if not ok or type(opts) ~= "table" then
    -- negatif cache: ayni dizinde tekrar tekrar denemeyelim
    cache[key] = false
    return nil
  end
  cache[key] = opts
  return opts
end

local function apply(bufnr, opts)
  if not opts then
    return
  end
  vim.bo[bufnr].shiftwidth = opts.shiftwidth
  vim.bo[bufnr].tabstop = opts.tabstop
  vim.bo[bufnr].softtabstop = opts.softtabstop
  vim.bo[bufnr].expandtab = opts.expandtab
end

--- Buffer icin formatter'dan turetilen indent ayarlari (test/teshis icin).
function M.resolve_for(bufnr)
  local ft = vim.bo[bufnr].filetype
  if not RESOLVERS[ft] then
    return nil
  end
  local ok, opts = pcall(resolve, bufnr, ft, vim.api.nvim_buf_get_name(bufnr))
  if not ok then
    return nil
  end
  return opts
end

function M.setup()
  local group = vim.api.nvim_create_augroup("IndentSync", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function(ev)
      local ft = vim.bo[ev.buf].filetype
      if not RESOLVERS[ft] then
        return
      end
      -- vim.schedule: built-in editorconfig ayni FileType zincirinde calisir,
      -- onun sonucu oturduktan sonra biz karar verelim.
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(ev.buf) then
          return
        end
        apply(ev.buf, M.resolve_for(ev.buf))
      end)
    end,
  })

  -- Proje config'i degisince cache'i bosalt.
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = {
      ".clang-format",
      "_clang-format",
      ".prettierrc*",
      "prettier.config.*",
      "package.json",
      "stylua.toml",
      ".stylua.toml",
      "rustfmt.toml",
      ".rustfmt.toml",
    },
    callback = clear_cache,
  })
end

-- ── Conform arguman uretimi ─────────────────────────────────────────────────

local function current_opts(bufnr)
  local bo = vim.bo[bufnr]
  local width = positive(bo.shiftwidth) or DEFAULT_WIDTH
  return {
    shiftwidth = width,
    tabstop = positive(bo.tabstop) or width,
    expandtab = bo.expandtab ~= false,
  }
end

--- clang-format stili: proje config varsa dosya, yoksa buffer ayarlarindan.
function M.clang_style(bufnr)
  local dir = dir_of(vim.api.nvim_buf_get_name(bufnr))
  if M.clang_config(dir) then
    return "-style=file"
  end
  local o = current_opts(bufnr)
  return string.format(
    "-style={BasedOnStyle: LLVM, IndentWidth: %d, TabWidth: %d, UseTab: %s, ColumnLimit: 120}",
    o.shiftwidth,
    o.tabstop,
    o.expandtab and "Never" or "ForIndentation"
  )
end

function M.rustfmt_width_args(dir)
  local path = M.rustfmt_config(dir)
  if path then
    local text = read_file(path)
    if type(text) == "string" and text:match("max_width%s*=%s*%d+") then
      return {}
    end
  end
  return { "--config", "max_width=120" }
end

--- prettier argumanlari: proje config varsa bos, yoksa buffer ayarlari.
function M.prettier_args(bufnr)
  local file = vim.api.nvim_buf_get_name(bufnr)
  local exe = executable("prettier")
  local path = (file ~= "" and exe) and M.prettier_config(file) or nil
  if path then
    local cfg = prettier_resolved(exe, file, path)
    -- printWidth proje config'inde yoksa varsayilan 120'yi uygula.
    if type(cfg) ~= "table" or cfg.printWidth == nil then
      return { "--print-width", "120" }
    end
    return {}
  end
  local o = current_opts(bufnr)
  return {
    "--tab-width",
    tostring(o.shiftwidth),
    o.expandtab and "--use-tabs=false" or "--use-tabs=true",
    "--print-width",
    "120",
  }
end

--- stylua argumanlari: proje config varsa bos, yoksa buffer ayarlari.
function M.stylua_args(bufnr)
  local dir = dir_of(vim.api.nvim_buf_get_name(bufnr))
  if M.stylua_config(dir) then
    return {}
  end
  local o = current_opts(bufnr)
  return {
    "--indent-width",
    tostring(o.shiftwidth),
    "--indent-type",
    o.expandtab and "Spaces" or "Tabs",
  }
end

return M
