-- obsidian.nvim (community fork, obsidian-nvim/obsidian.nvim)
-- Vault entegrasyonu: wikilink tamamlama, link takibi, backlinks, tag'ler.
-- Görseller (conceal vb.) render-markdown üstlenir → ui.enable = false.
return {
  "obsidian-nvim/obsidian.nvim",
  version = "*",
  lazy = true,
  ft = "markdown",
  opts = {
    workspaces = {
      { name = "personal",         path = vim.fn.expand("~/NextCloud/Vaults/Personal-Vault") },
      { name = "lectures",         path = vim.fn.expand("~/NextCloud/School/Lectures-Vault") },
      { name = "maneviai",         path = vim.fn.expand("~/NextCloud/Vaults/ManeviAI-Vault") },
      { name = "game-noter",       path = vim.fn.expand("~/NextCloud/GameNoter/GameNoter-Vault") },
      { name = "paptakip",         path = vim.fn.expand("~/Documents/Karamanlar_Business/pap_dokumanlari/PapTakip-Vault") },
      { name = "karamanlar-panel", path = vim.fn.expand("~/Documents/Karamanlar_Business/karamanlar_panel_dokumanlari/KaramanlarPanel-Vault") },
    },
    -- Vault dışındaki dosyalarda yeni not mevcut dosyanın yanına
    new_notes_location = "current_dir",
    -- Modern komut stili (:Obsidian follow_link vb.); eski adlar 4.0'da kalkıyor
    legacy_commands = false,
    -- [[Not Adı]] (Obsidian doğal dili; varsayılan zaten "wiki")
    link = { style = "wiki" },
    -- nvim-cmp otomatik algılanır (ayrıca blink.cmp de desteklenir)
    picker = { name = "telescope.nvim" },
    -- render-markdown görselleri üstlenir; çift render önlenir
    ui = { enable = false },
    -- lualine/statusline ile çakışmasın, yazım yüzeyi temiz kalsın
    statusline = { enabled = false },
    footer = { enabled = false },
  },
}