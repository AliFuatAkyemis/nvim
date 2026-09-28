-- ftplugin/markdown.lua
-- Obsidian-tarzı markdown kısayolları. Yalnızca markdown filetype'ında yüklenir.
-- Tüm mapping'ler buffer-local'dir; diğer dosya türleri etkilenmez.

local M = require("config.markdown")

local function map(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { buffer = true, silent = true, desc = desc })
end

-- ----------------------------------------------------------------- emphasis
-- Auto: normal/visual. Insert işlemi için mod açıkça iletilir (bkz. config.markdown).
map({ "n", "v" }, "<C-b>", function() M.toggle("bold") end, "Kalın")
map("i", "<C-b>", function() M.toggle("bold", "i") end, "Kalın")

map({ "n", "v" }, "<C-i>", function() M.toggle("italic") end, "İtalik")
map("i", "<C-i>", function() M.toggle("italic", "i") end, "İtalik")

map({ "n", "v" }, "<C-e>", function() M.toggle("code") end, "Inline code")
map("i", "<C-e>", function() M.toggle("code", "i") end, "Inline code")

map({ "n", "v" }, "<C-s>", function() M.toggle("strike") end, "Üstü çizili")
map("i", "<C-s>", function() M.toggle("strike", "i") end, "Üstü çizili")

map({ "n", "v" }, "<C-l>", function() M.toggle("highlight") end, "Vurgu")
map("i", "<C-l>", function() M.toggle("highlight", "i") end, "Vurgu")

-- ----------------------------------------------------------------- link
map({ "n", "v", "i" }, "<C-k>", function() M.insert_link() end, "Link ekle")
map({ "n", "v", "i" }, "<leader>l", function() M.insert_wikilink() end, "Wikilink")

-- ------------------------------------------------------------- başlık
for level = 1, 6 do
  map({ "n", "i" }, "<C-" .. level .. ">", function() M.set_heading(level) end, "Başlık " .. level)
end

-- --------------------------------------------------------------- checkbox
map({ "n", "i" }, "<C-Enter>", M.toggle_checkbox, "Checkbox çevir")

-- ----------------------------------------------------------------- alıntı
map({ "n", "v" }, "<leader>q", M.toggle_quote, "Alıntı")

-- NOTE: <CR> (smart_action) ve ]o/[o (nav_link) mapping'lerini obsidian.nvim
-- kendisi kurar; burada tekrarlanmaz (çift tanım/örgün kaynak karışıklığı
-- olmasın). gf varsayılan davranışı korunur; link takibi <CR> ile yapılır.

-- ----------------------------------------------------------------- Tab
-- Neovim "CTRL-I ancak iki tuş da map edilirse Tab'dan ayrılır" kuralı:
-- markdown'da <Tab> davranışı bilinçli olarak korunur/güvence altına alınır.
map("n", "<Tab>", function() M.toggle("italic", "n") end, "İtalik (Tab)")
map("v", "<Tab>", ">gv", "Girinti")
map("v", "<S-Tab>", "<gv", "Girinti azalt")

-- Insert: cmp tamamlama / snippet davranışını birebir koru
map("i", "<Tab>", function()
  local cmp = require("cmp")
  local luasnip = require("luasnip")
  if cmp.visible() then
    cmp.select_next_item()
  elseif luasnip.expand_or_jumpable() then
    luasnip.expand_or_jump()
  else
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("\t", true, false, true), "n", false)
  end
end, "Tamamla / Tab")

map("i", "<S-Tab>", function()
  local cmp = require("cmp")
  local luasnip = require("luasnip")
  if cmp.visible() then
    cmp.select_prev_item()
  elseif luasnip.jumpable(-1) then
    luasnip.jump(-1)
  end
end, "Tamamla geri / Shift-Tab")