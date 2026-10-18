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

-- Vurgu <leader>lh: <C-l> global kelime-atlama alias'ına bırakıldı (bkz.
-- lua/config/keymaps.lua), bu yüzden buffer-local olarak tanımlanmaz.
map({ "n", "v" }, "<leader>lh", function() M.toggle("highlight") end, "Vurgu")
map("i", "<leader>lh", function() M.toggle("highlight", "i") end, "Vurgu")

-- ----------------------------------------------------------------- link
map({ "n", "v", "i" }, "<C-k>", function() M.insert_link() end, "Link ekle")
-- Wikilink yalnızca normal/visual: insert modda <leader>=space olduğundan her
-- boşluk tuşu "bekleyen mapping öneki"ne döner ve gecikmeli yazılır.
map({ "n", "v" }, "<leader>l", function() M.insert_wikilink() end, "Wikilink")

-- ------------------------------------------------------------- başlık
for level = 1, 6 do
  map({ "n", "i" }, "<C-" .. level .. ">", function() M.set_heading(level) end, "Başlık " .. level)
end

-- --------------------------------------------------------------- checkbox
map({ "n", "i" }, "<C-Enter>", M.toggle_checkbox, "Checkbox çevir")

-- ------------------------------------------------------------------ liste
-- Enter: bulunulan listenin türüne göre sonraki maddeyi açar.
-- Shift+Enter: aynı maddeyi metin hizasında alt satırda sürdürür.
-- cmp/autopairs davranışı korunur: önce tamamlama onayı, sonra liste, aksi
-- halde mevcut insert <CR> davranışı (autopairs pair-split / düz satır).
local function list_cr()
  local ok_cmp, cmp = pcall(require, "cmp")
  if ok_cmp and cmp.visible() and cmp.get_active_entry() then
    cmp.confirm({ select = true })
    return
  end
  if M.new_list_item() then
    return
  end
  local ok_np, np = pcall(require, "nvim-autopairs")
  if ok_np then
    vim.api.nvim_feedkeys(np.autopairs_cr(), "n", false)
  else
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
  end
end

local function list_shift_cr()
  local ok_cmp, cmp = pcall(require, "cmp")
  if ok_cmp and cmp.visible() and cmp.get_active_entry() then
    cmp.confirm({ select = true })
    return
  end
  if M.soft_break() then
    return
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
end

map("i", "<CR>", list_cr, "Sonraki madde / Enter")
map("i", "<S-CR>", list_shift_cr, "Madde içi satır (Shift+Enter)")

-- Normal-mod `o` (satır sonundan Enter eşdeğeri) da aynı liste devamını
-- uygular. `O` (üste aç) bilinçli olarak varsayılan kalır.
map("n", "o", function()
  if M.new_list_item({ require_end = false }) then
    -- `!` (append) sart: normal moddan gelindiginde nvim_win_set_cursor
    -- satir sonunu bir karakter kirpar; `6. |` kalirsa bos Enter isareti
    -- kaldiramaz. Append imleci boslugun sagina tasir.
    vim.cmd("startinsert!")
    return
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("o", true, false, true), "n", false)
end, "Alt satırda sonraki madde (o)")

-- Silme (ve her tür buffer değişimi) sonrası liste numaralamasını güncelle;
-- bloğun ardışık sırası her zaman korunur. Insert modda ve komut satırında
-- dokunulmaz (yazarken araya girip numara değiştirmesin). Normal-mod
-- değişiklikleri bir sonraki tick'te, blok yerleştikten sonra işlenir.
local renumber_scheduled = false
vim.api.nvim_buf_attach(0, false, {
  on_lines = function(_, bufnr)
    if renumber_scheduled then
      return
    end
    renumber_scheduled = true
    vim.schedule(function()
      local m = vim.fn.mode()
      local first = m:sub(1, 1)
      if first ~= "i" and first ~= "c" and m ~= "t" and vim.bo[bufnr].modifiable then
        M.renumber(bufnr)
      end
      renumber_scheduled = false
    end)
  end,
})

-- Insert'tan çıkınca (ör. bir maddenin numarasını değiştirdikten sonra) listeyi
-- yeniden numarala; güncelleme için ekstra tuşa basmak gerekmez.
vim.api.nvim_create_autocmd("InsertLeave", {
  buffer = 0,
  callback = function()
    if vim.bo.modifiable then
      M.renumber()
    end
  end,
})

-- ----------------------------------------------------------------- alıntı
map({ "n", "v" }, "<leader>q", M.toggle_quote, "Alıntı")

-- NOTE: Normal-mod <CR> (smart_action) ve ]o/[o (nav_link) mapping'lerini
-- obsidian.nvim kendisi kurar; burada tekrarlanmaz (çift tanım/örgün kaynak
-- karışıklığı olmasın). Insert-mod <CR>/<S-CR> ise liste davranışı için
-- buffer-local olarak yukarıda tanımlanır. gf varsayılan davranışı korunur;
-- link takibi normal modda <CR> ile yapılır.

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