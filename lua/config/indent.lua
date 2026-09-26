-- lua/config/indent.lua
-- VSCode onEnterRules mantığıyla custom indentexpr
-- html / javascript / typescript / jsx / tsx için Treesitter indent'in yerine geçer

local M = {}

-- HTML'deki "void element" (boş element) listesi. Bu etiketlerin sonuna kapatma takısı
-- konulmasa bile (HTML5 standardı) alt satırda girinti (indent) verilmemelidir.
local void_elements = {
  area = true,
  base = true,
  br = true,
  col = true,
  embed = true,
  hr = true,
  img = true,
  input = true,
  link = true,
  meta = true,
  param = true,
  source = true,
  track = true,
  wbr = true,
}

-- Detect Treesitter language at a specific line
local function get_lang_at_line(lnum)
  local bufnr = vim.api.nvim_get_current_buf()
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return vim.bo[bufnr].filetype
  end

  pcall(parser.parse, parser, true)

  local row = lnum - 1
  local tree = parser:language_for_range({ row, 0, row, 0 })
  if tree then
    return tree:lang()
  end

  return vim.bo[bufnr].filetype
end

-- Satır sonundaki (veya önceki satırlardaki) tag ismini bulup void element olup olmadığını kontrol eder.
local function is_not_void_element(prev_lnum)
  local line = vim.fn.getline(prev_lnum)
  if not line:match(">%s*$") then
    return true
  end

  local lnum = prev_lnum
  while lnum > 0 do
    -- Safeguard: If we cross the boundary into non-HTML/non-Angular code, stop!
    local lang = get_lang_at_line(lnum)
    if not (lang == "html" or lang == "angular" or lang == "htmlangular") then
      break
    end

    local cur_line = vim.fn.getline(lnum)

    -- Eğer aradığımız son satır ise, sonundaki > işaretini kaldırıp arayalım
    if lnum == prev_lnum then
      cur_line = cur_line:gsub(">%s*$", "")
    end

    -- Satırdaki son açılış tag'ini bulalım: <tag_name
    local tag_name = cur_line:match("<([%w%-%.:]+)[^>]*$")
    if tag_name then
      return not void_elements[tag_name:lower()]
    end

    -- Eğer satırda `>` karakteri varsa ve bu başlangıç satırı değilse taramayı durdurabiliriz
    if lnum ~= prev_lnum and cur_line:match(">") then
      break
    end
    if prev_lnum - lnum > 10 then
      break
    end
    lnum = lnum - 1
  end

  return true
end

-- Satırda kapatılmamış bir HTML/JSX etiketi (<div veya <li gibi) olup olmadığını denetler.
-- Karşılaştırma operatörleri (x < y) ile çakışmaması için önünde alfanumerik karakter olmamalıdır.
local function is_unclosed_tag(prev_lnum)
  local line = vim.fn.getline(prev_lnum)
  -- Satırın başından başlayan etiketler (örn: <li ) veya kelime karakteri olmayan bir karakterden sonra gelenler (örn: = <div )
  return line:match("^%s*<[%a_][%w%-%.:]*[^>]*$") ~= nil or line:match("[^%w_]<[%a_][%w%-%.:]*[^>]*$") ~= nil
end

-- Kural tablosu — ilk eşleşen kural kazanır
-- mode        : "html" | "js" | nil (both)
-- before      : önceki satıra uygulanan Lua pattern (eşleşmeli)
-- before_not  : önceki satıra uygulanan Lua pattern (eşleşmemeli)
-- cond        : özel doğrulama fonksiyonu (true dönerse kural uygulanır)
-- current     : hesaplanan yeni satıra uygulanan Lua pattern (eşleşmeli)
-- action      : "indent" | "outdent" | "none"
local rules = {
  -- ── Boş Bloklar → none ───────────────────────────────────────────────────
  -- Eğer önceki satır açılışla bitiyor ve mevcut satır kapanışla başlıyorsa,
  -- aynı hizada kalmalıdır (outdent uygulanmaz).
  {
    mode = "html",
    before = ">%s*$",
    before_not = { "/>%s*$", "</[%w%-%.:]+>%s*$" },
    cond = is_not_void_element,
    current = "^%s*</",
    action = "none",
  },
  { before = "{%s*$", current = "^%s*}", action = "none" },
  { mode = "js", before = "%(%s*$", current = "^%s*%)", action = "none" },
  { mode = "js", before = "%[%s*$", current = "^%s*%]", action = "none" },

  -- ── Kapanış → outdent ────────────────────────────────────────────────────
  -- Mevcut satır kapanış ile başlıyorsa bir seviye geri al (outdent)
  { mode = "html", current = "^%s*</", action = "outdent" },
  { current = "^%s*}", action = "outdent" },
  { mode = "js", current = "^%s*%)", action = "outdent" },
  { mode = "js", current = "^%s*%]", action = "outdent" },
  { mode = "html", current = "^%s*/>", action = "outdent" },
  { mode = "html", current = "^%s*>", action = "outdent" },
  { mode = "html", current = "^%s*['\"]%s*$", action = "outdent" },

  -- ── Açılış → indent ──────────────────────────────────────────────────────
  -- Önceki satır açık tag ile bitiyorsa: <head>, <div class="x">
  -- Hariç: /> (self-closing)  ve  </tag> (closing tag)
  {
    mode = "html",
    before = ">%s*$",
    before_not = { "/>%s*$", "</[%w%-%.:]+>%s*$" },
    cond = is_not_void_element,
    action = "indent",
  },
  -- Önceki satırda kapatılmamış etiket açılışı varsa (örn: <li, <div class="x")
  {
    mode = "html",
    cond = is_unclosed_tag,
    action = "indent",
  },
  -- Önceki satır tırnakla açılan bir değer ataması ise (örn: style=", class=")
  {
    mode = "html",
    before = "=%s*['\"]%s*$",
    action = "indent",
  },
  -- Önceki satır { ile bitiyorsa
  { before = "{%s*$", action = "indent" },
  -- Önceki satır ( ile bitiyorsa
  { mode = "js", before = "%(%s*$", action = "indent" },
  -- Önceki satır [ ile bitiyorsa
  { mode = "js", before = "%[%s*$", action = "indent" },
}

function M.get_indent()
  local lnum = vim.v.lnum
  local prev_lnum = vim.fn.prevnonblank(lnum - 1)
  if prev_lnum == 0 then
    return 0
  end

  local prev_line = vim.fn.getline(prev_lnum)
  local current_line = vim.fn.getline(lnum)
  local base_indent = vim.fn.indent(prev_lnum)
  local sw = vim.fn.shiftwidth()

  local lang = get_lang_at_line(lnum)
  local is_html_mode = (lang == "html" or lang == "angular" or lang == "htmlangular")
  local is_js_mode = (
    lang == "typescript"
    or lang == "javascript"
    or lang == "typescriptreact"
    or lang == "javascriptreact"
  )

  for _, rule in ipairs(rules) do
    -- Filter rules by language mode
    local mode_ok = true
    if rule.mode == "html" and not is_html_mode then
      mode_ok = false
    elseif rule.mode == "js" and not is_js_mode then
      mode_ok = false
    end

    if mode_ok then
      -- before: eşleşmeli
      local before_ok = (rule.before == nil) or (prev_line:match(rule.before) ~= nil)

      -- before_not: hiçbiri eşleşmemeli (tablo veya string kabul eder)
      local before_not_ok = true
      if rule.before_not ~= nil then
        local patterns = type(rule.before_not) == "table" and rule.before_not or { rule.before_not }
        for _, pat in ipairs(patterns) do
          if prev_line:match(pat) then
            before_not_ok = false
            break
          end
        end
      end

      -- current: eşleşmeli
      local current_ok = (rule.current == nil) or (current_line:match(rule.current) ~= nil)

      -- cond: custom condition function
      local cond_ok = (rule.cond == nil) or rule.cond(prev_lnum, lnum)

      if before_ok and before_not_ok and current_ok and cond_ok then
        if rule.action == "indent" then
          return base_indent + sw
        end
        if rule.action == "outdent" then
          return math.max(0, base_indent - sw)
        end
        if rule.action == "none" then
          return base_indent
        end
      end
    end
  end

  return base_indent -- default: önceki satırla aynı hiza (autoindent)
end

return M
