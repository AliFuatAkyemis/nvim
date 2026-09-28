-- config/markdown.lua
-- Obsidian-tarzı markdown düzenleme çekirdeği.
-- Yalnızca ftplugin/markdown.lua (markdown filetype'ı) üzerinden çağrılır;
-- global hiçbir şeyi değiştirmez.

local M = {}

M.styles = {
  bold      = { left = "**", right = "**" },
  italic    = { left = "*",  right = "*"  },
  code      = { left = "`",  right = "`"  },
  strike    = { left = "~~", right = "~~" },
  highlight = { left = "==", right = "==" },
}

local function style_for(style)
  if type(style) == "string" then
    return M.styles[style]
  end
  return style
end

-- ---------------------------------------------------------------- iskeyword
-- iskeyword tabanlı karakter sınıflandırması (Türkçe ünlüler dahil, UTF-8)
local function make_keyword_check()
  local ranges, singles = {}, {}
  local alpha = false
  local fmt = vim.o.iskeyword or "@,48-57,_,192-255"
  for item in fmt:gmatch("[^,]+") do
    if item == "@" or item == "@-@" then
      alpha = true
    elseif item:match("^%d+%-%d+$") then
      local lo, hi = item:match("^(%d+)-(%d+)$")
      ranges[#ranges + 1] = { tonumber(lo), tonumber(hi) }
    elseif #item == 1 then
      singles[vim.fn.char2nr(item)] = true
    end
  end
  return function(ch)
    local cp = vim.fn.char2nr(ch)
    if singles[cp] then
      return true
    end
    for _, r in ipairs(ranges) do
      if cp >= r[1] and cp <= r[2] then
        return true
      end
    end
    if alpha then
      -- ASCII harfler + Latin-1 + Latin Extended-A/B (ş, ğ, ı, İ vb. dahil)
      if (cp >= 65 and cp <= 90)
        or (cp >= 97 and cp <= 122)
        or (cp >= 0x100 and cp <= 0x24F)
      then
        return true
      end
    end
    return false
  end
end
local is_kw = make_keyword_check()

-- İmlecin içinde/yanında olduğu kelimenin [başlangıç, bitiş) bayt aralığı (0-bazlı).
-- İmleç kelime sonundaysa (insert noktası) sondaki kelime döner. Kelime yoksa nil.
local function token_range(line, byte_col)
  if not line or #line == 0 then
    return nil
  end
  local n = vim.fn.strchars(line)
  local ci = vim.str_utfindex(line, math.min(byte_col, #line))
  if ci >= n then
    ci = n - 1
  end
  if not is_kw(vim.fn.strcharpart(line, ci, 1)) then
    if ci > 0 and is_kw(vim.fn.strcharpart(line, ci - 1, 1)) then
      ci = ci - 1
    else
      return nil
    end
  end
  local s, e = ci, ci + 1
  while s > 0 and is_kw(vim.fn.strcharpart(line, s - 1, 1)) do
    s = s - 1
  end
  while e < n and is_kw(vim.fn.strcharpart(line, e, 1)) do
    e = e + 1
  end
  return vim.str_byteindex(line, s), vim.str_byteindex(line, e)
end

-- [s,e) aralığındaki metin verilen delimiter'larla sarılı mı?
-- Tek karakterli delimiter'larda ("*", "`") daha uzun bir dizinin parçası
-- olmadığı doğrulanır (örn. **word** üzerinde italik → sar, açma).
local function is_wrapped(line, s, e, left, right)
  local len = #line
  if s < #left or e + #right > len then
    return false
  end
  if line:sub(s - #left + 1, s) ~= left or line:sub(e + 1, e + #right) ~= right then
    return false
  end
  local c = left:sub(1, 1)
  if #left == 1 then
    if s > #left and line:sub(s - #left, s - #left) == c then
      return false
    end
    if e + #right < len and line:sub(e + #right + 1, e + #right + 1) == c then
      return false
    end
  end
  return true
end

-- Kelime sarma/soyma (normal + insert ortak mantık)
local function wrap_token(style, lnum, s, e, stay_insert)
  local line = vim.fn.getline(lnum)
  if is_wrapped(line, s, e, style.left, style.right) then
    local inner = line:sub(s - #style.left + 1, e + #style.right)
    inner = inner:sub(#style.left + 1, #inner - #style.right)
    vim.api.nvim_buf_set_text(0, lnum - 1, s - #style.left, lnum - 1, e + #style.right, { inner })
    local col = stay_insert and (s - #style.left + #inner) or (s - #style.left)
    vim.api.nvim_win_set_cursor(0, { lnum, col })
  else
    local inner = line:sub(s + 1, e)
    vim.api.nvim_buf_set_text(0, lnum - 1, s, lnum - 1, e, { style.left .. inner .. style.right })
    local col = stay_insert and (e + #style.left) or (s + #style.left)
    vim.api.nvim_win_set_cursor(0, { lnum, col })
  end
end

-- Boşta delimiter çifti ekle, imleci ortaya koy
local function wrap_empty(style, lnum, c, stay_insert)
  vim.api.nvim_buf_set_text(0, lnum - 1, c, lnum - 1, c, { style.left .. style.right })
  vim.api.nvim_win_set_cursor(0, { lnum, c + #style.left })
  if not stay_insert then
    vim.cmd("startinsert")
  end
end

-- ------------------------------------------------------------------ visual
-- Aktif visual seçimin geometrisi. Headless/aktif visual'da '< '> mark'ları ve
-- visualmode() güvenilir olmadığı için mode() + "v" işareti (anchor) + imleç
-- konumundan hesaplanır.
-- Dönüş: { l1, c1, l2, c2, linewise } — c1 0-bazlı başlangıç, c2 özel bitiş.
local function visual_geometry()
  local m = vim.fn.mode()
  if m:sub(1, 1) ~= "v" and m:sub(1, 1) ~= "V" and m ~= "\22" then
    return nil
  end
  local linewise = m:sub(1, 1) == "V"
  local a = vim.fn.getpos("v")
  local cur = vim.api.nvim_win_get_cursor(0)
  local al, ac = a[2], a[3] - 1 -- 0-bazlı, kapsayıcı başlangıç
  local cl, cc = cur[1], cur[2] -- 0-bazlı, kapsayıcı bitiş
  if al > cl or (al == cl and ac > cc) then
    al, ac, cl, cc = cl, cc, al, ac -- geriye doğru seçimi normalleştir
  end
  if linewise then
    return { l1 = al, c1 = 0, l2 = cl, c2 = math.huge, linewise = true }
  end
  return { l1 = al, c1 = ac, l2 = cl, c2 = cc + 1, linewise = false }
end

local function get_visual_text(g)
  if g.linewise then
    return table.concat(vim.api.nvim_buf_get_lines(0, g.l1 - 1, g.l2, false), "\n")
  end
  local last = vim.fn.getline(g.l2)
  local ec = math.min(g.c2, #last)
  return table.concat(vim.api.nvim_buf_get_text(0, g.l1 - 1, g.c1, g.l2 - 1, ec, {}), "\n")
end

local function set_visual_text(g, rows)
  if g.linewise then
    vim.api.nvim_buf_set_lines(0, g.l1 - 1, g.l2, false, rows)
  else
    local last = vim.fn.getline(g.l2)
    local ec = math.min(g.c2, #last)
    vim.api.nvim_buf_set_text(0, g.l1 - 1, g.c1, g.l2 - 1, ec, rows)
  end
end

-- Değişiklikten sonra seçimi yeni aralığa taşı ve gv ile yeniden seç
local function reselect(g, sel_len, left, right, added)
  if g.linewise then
    vim.fn.setpos("'<", { 0, g.l1, 1, 0 })
    local last = vim.fn.getline(g.l2)
    vim.fn.setpos("'>", { 0, g.l2, #last, 0 })
    vim.cmd("normal! gv")
    return
  end
  if g.l1 == g.l2 then
    vim.fn.setpos("'<", { 0, g.l1, g.c1 + 1, 0 })
    if added then
      vim.fn.setpos("'>", { 0, g.l1, g.c1 + sel_len + #left + #right, 0 })
    else
      vim.fn.setpos("'>", { 0, g.l1, g.c1 + sel_len - #left - #right, 0 })
    end
  else
    vim.fn.setpos("'<", { 0, g.l1, g.c1 + 1, 0 })
    if added then
      vim.fn.setpos("'>", { 0, g.l2, g.c2 + #right, 0 })
    else
      vim.fn.setpos("'>", { 0, g.l2, g.c2 - #right, 0 })
    end
  end
  vim.cmd("normal! gv")
end

local function toggle_visual(style)
  local g = visual_geometry()
  if not g then
    return
  end
  local sel = get_visual_text(g)
  local newsel, added
  if sel ~= ""
    and sel:sub(1, #style.left) == style.left
    and sel:sub(-#style.right) == style.right
    and #sel > #style.left + #style.right
  then
    newsel = sel:sub(#style.left + 1, #sel - #style.right)
    added = false
  else
    newsel = style.left .. sel .. style.right
    added = true
  end
  set_visual_text(g, vim.split(newsel, "\n", { plain = true }))
  reselect(g, #sel, style.left, style.right, added)
end

-- ------------------------------------------------------- normal + insert
local function toggle_normal_or_insert(style, insert)
  local lnum = vim.fn.line(".")
  local line = vim.fn.getline(lnum)
  local c = vim.fn.col(".") - 1
  local s, e = token_range(line, c)
  if s then
    wrap_token(style, lnum, s, e, insert)
  else
    wrap_empty(style, lnum, c, insert)
  end
end

function M.toggle(style, mode)
  style = style_for(style)
  if not style then
    return
  end
  if not mode then
    -- Visual mod nvim_get_mode ile güvenilir; insert mod bu ortamlarda
    -- "n" görünür, ftplugin onu "i" göndererek çözer.
    local gm = vim.api.nvim_get_mode().mode
    local first = gm:sub(1, 1)
    if first == "v" or first == "V" or gm == "\22" then
      mode = "v"
    else
      mode = "n"
    end
  end
  if mode == "v" then
    toggle_visual(style)
  elseif mode == "i" then
    toggle_normal_or_insert(style, true)
  else
    toggle_normal_or_insert(style, false)
  end
end

-- ------------------------------------------------------------------ başlık
-- Satırı N düzeyine getir; aynısıysa kaldır
function M.set_heading(level)
  level = math.max(1, math.min(6, level))
  local lnum = vim.fn.line(".")
  local line = vim.fn.getline(lnum)
  local hashes, rest = line:match("^(#+)%s?(.*)$")
  local new
  if hashes and #hashes == level then
    new = rest
  else
    local _, rest2 = line:match("^(#*)%s?(.*)$")
    new = string.rep("#", level) .. " " .. rest2
  end
  vim.api.nvim_buf_set_lines(0, lnum - 1, lnum, false, { new })
  local col = math.min(vim.fn.col(".") - 1, #new)
  vim.api.nvim_win_set_cursor(0, { lnum, col })
end

-- ---------------------------------------------------------------- checkbox
-- - [ ] ↔ - [x]; listede değilse - [ ] oluştur
function M.toggle_checkbox()
  local lnum = vim.fn.line(".")
  local line = vim.fn.getline(lnum)
  local indent, marker, state, text = line:match("^(%s*)([-*+])%s+%[([%sxX>~!])%]%s*(.*)$")
  if indent then
    local ch
    if state == " " then
      ch = "x"
    elseif state == "x" or state == "X" then
      ch = " "
    else
      ch = state
    end
    vim.api.nvim_buf_set_lines(0, lnum - 1, lnum, false, { indent .. marker .. " [" .. ch .. "] " .. text })
    return
  end
  local indent2, marker2, text2 = line:match("^(%s*)([-*+])%s+(.*)$")
  if indent2 then
    vim.api.nvim_buf_set_lines(0, lnum - 1, lnum, false, { indent2 .. marker2 .. " [ ] " .. text2 })
    return
  end
  vim.api.nvim_buf_set_lines(0, lnum - 1, lnum, false, { "- [ ] " .. line })
end

-- ---------------------------------------------------------------- alıntı
-- Satır(lar)ı > ile önekle / > kaldır
function M.toggle_quote()
  local mode = vim.fn.mode()
  if mode:sub(1, 1) == "v" or mode:sub(1, 1) == "V" or mode == "\22" then
    local g = visual_geometry()
    if not g then
      return
    end
    for ln = g.l1, g.l2 do
      local line = vim.fn.getline(ln)
      local indent, extra = line:match("^(%s*)>(%s?)")
      if indent then
        local strip = #indent + 1 + #extra
        vim.api.nvim_buf_set_lines(0, ln - 1, ln, false, { line:sub(strip + 1) })
      else
        vim.api.nvim_buf_set_lines(0, ln - 1, ln, false, { "> " .. line })
      end
    end
    vim.cmd("normal! gv")
  else
    local lnum = vim.fn.line(".")
    local line = vim.fn.getline(lnum)
    local indent, extra = line:match("^(%s*)>(%s?)")
    if indent then
      local strip = #indent + 1 + #extra
      vim.api.nvim_buf_set_lines(0, lnum - 1, lnum, false, { line:sub(strip + 1) })
    else
      vim.api.nvim_buf_set_lines(0, lnum - 1, lnum, false, { "> " .. line })
    end
  end
end

-- -------------------------------------------------------------------- link
local function visual_replace_with_insert(g, tmpl, cursor_delta)
  local sel = get_visual_text(g)
  local newtext = tmpl:gsub("%%SEL%%", sel)
  set_visual_text(g, { newtext })
  vim.api.nvim_win_set_cursor(0, { g.l1, g.c1 + #sel + cursor_delta })
end

-- [metin](url), imleç url'de, insert modda
function M.insert_link()
  local mode = vim.fn.mode()
  if mode:sub(1, 1) == "v" or mode:sub(1, 1) == "V" or mode == "\22" then
    local g = visual_geometry()
    if not g then
      return
    end
    visual_replace_with_insert(g, "[%SEL%](url)", 3)
    vim.cmd("startinsert")
    return
  end
  local insert = mode:sub(1, 1) == "i"
  local lnum = vim.fn.line(".")
  local line = vim.fn.getline(lnum)
  local c = vim.fn.col(".") - 1
  local s, e = token_range(line, c)
  if s then
    local inner = line:sub(s + 1, e)
    vim.api.nvim_buf_set_text(0, lnum - 1, s, lnum - 1, e, { "[" .. inner .. "](url)" })
    vim.api.nvim_win_set_cursor(0, { lnum, s + #inner + 3 })
  else
    vim.api.nvim_buf_set_text(0, lnum - 1, c, lnum - 1, c, { "[](url)" })
    vim.api.nvim_win_set_cursor(0, { lnum, c + 3 })
  end
  if not insert then
    vim.cmd("startinsert")
  end
end

-- |[[seçim]] / [[ ]]|
function M.insert_wikilink()
  local mode = vim.fn.mode()
  if mode:sub(1, 1) == "v" or mode:sub(1, 1) == "V" or mode == "\22" then
    local g = visual_geometry()
    if not g then
      return
    end
    local sel = get_visual_text(g)
    set_visual_text(g, { "[[" .. sel .. "]]" })
    vim.api.nvim_win_set_cursor(0, { g.l1, g.c1 + #sel + 2 })
    return
  end
  local insert = mode:sub(1, 1) == "i"
  local lnum = vim.fn.line(".")
  local line = vim.fn.getline(lnum)
  local c = vim.fn.col(".") - 1
  local s, e = token_range(line, c)
  if s then
    local inner = line:sub(s + 1, e)
    vim.api.nvim_buf_set_text(0, lnum - 1, s, lnum - 1, e, { "[[" .. inner .. "]]" })
    vim.api.nvim_win_set_cursor(0, { lnum, s + #inner + 2 })
  else
    vim.api.nvim_buf_set_text(0, lnum - 1, c, lnum - 1, c, { "[[ ]]" })
    vim.api.nvim_win_set_cursor(0, { lnum, c + 2 })
  end
  if not insert then
    vim.cmd("startinsert")
  end
end

return M