return {
  {
    "hrsh7th/nvim-cmp",
    version = false, -- last release is way too old
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-cmdline",
      "saadparwaiz1/cmp_luasnip",
      "L3MON4D3/LuaSnip",
      "rafamadriz/friendly-snippets",
      "onsails/lspkind.nvim",
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")
      local lspkind = require("lspkind")

      luasnip.filetype_extend("htmlangular", { "html" })
      require("luasnip.loaders.from_vscode").lazy_load()
      -- Force load lazy-loaded snippets for the current buffer
      require("luasnip.loaders").load_lazy_loaded(vim.api.nvim_get_current_buf())

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        window = {
          completion = cmp.config.window.bordered(),
          documentation = cmp.config.window.bordered(),
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.abort(),
          ["<CR>"] = cmp.mapping({
            i = function(fallback)
              local cursor = vim.api.nvim_win_get_cursor(0)
              local before = vim.api.nvim_get_current_line():sub(1, cursor[2])
              local typing = before:match("[%w_]$") ~= nil
              if not cmp.visible() then
                fallback()
                return
              end
              local entry = cmp.get_selected_entry()
              local entry_row = entry
                and entry.context
                and entry.context.cursor
                and entry.context.cursor.row
              if entry and entry_row == cursor[1] then
                cmp.confirm({ select = true })
                return
              end
              -- Stale entries from another line: confirming deletes every line
              -- between (nvim-cmp core.confirm). Drop them and, if a word was
              -- typed here, re-query and confirm the fresh first match.
              cmp.abort()
              if typing then
                cmp.complete()
                vim.defer_fn(function()
                  if vim.api.nvim_get_mode().mode:sub(1, 1) ~= "i" then
                    return
                  end
                  local fresh = cmp.get_selected_entry()
                  local fresh_row = fresh
                    and fresh.context
                    and fresh.context.cursor
                    and fresh.context.cursor.row
                  if fresh and fresh_row == vim.api.nvim_win_get_cursor(0)[1] then
                    cmp.confirm({ select = true })
                  end
                end, 100)
              else
                fallback()
              end
            end,
            s = cmp.mapping.confirm({ select = true }),
            c = cmp.mapping.confirm({ select = false }),
          }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "unitykit", priority = 1000 },
          { name = "nvim_lsp" },
          { name = "luasnip", dup = 1 },
        }, {
          { name = "buffer" },
          { name = "path" },
        }),
        formatting = {
          format = lspkind.cmp_format({
            mode = "symbol_text",
            maxwidth = 50,
            ellipsis_char = "...",
          }),
        },
        matching = {
          disallow_fuzzy_matching = false,
          disallow_fullprefix_matching = false,
          disallow_partial_fuzzy_matching = false,
          disallow_partial_matching = false,
          disallow_prefix_unmatching = false,
        },
        sorting = {
          priority_weight = 2,
          comparators = {
            cmp.config.compare.offset,
            cmp.config.compare.exact,
            cmp.config.compare.score,
            cmp.config.compare.recently_used,
            cmp.config.compare.locality,
            cmp.config.compare.kind,
            cmp.config.compare.sort_text,
            cmp.config.compare.length,
            cmp.config.compare.order,
          },
        },
      })

      -- Use buffer source for `/` and `?` (if you enabled `native_menu`, this won't work anymore).
      cmp.setup.cmdline({ "/", "?" }, {
        mapping = cmp.mapping.preset.cmdline(),
        sources = {
          { name = "buffer" },
        },
      })

      -- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
      cmp.setup.cmdline(":", {
        mapping = cmp.mapping.preset.cmdline(),
        sources = cmp.config.sources({
          { name = "path" },
        }, {
          { name = "cmdline" },
        }),
      })
    end,
  },
}
