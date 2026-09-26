return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      -- Parsers to install (grid/add here as needed)
      local ensure_installed = {
        "c",
        "lua",
        "vim",
        "vimdoc",
        "query",
        "python",
        "javascript",
        "typescript",
        "tsx",
        "html",
        "css",
        "json",
        "yaml",
        "bash",
        "dockerfile",
        "go",
        "rust",
        "cpp",
        "markdown",
        "markdown_inline",
        "latex",
        "angular",
        "kotlin",
      }

      -- Install parsers asynchronously
      require("nvim-treesitter").install(ensure_installed)

      -- angular parser is registered for the `htmlangular` filetype
      vim.treesitter.language.register("angular", "htmlangular")

      -- Enable treesitter highlighting/indentation per filetype (this is the
      -- pattern recommended by the current nvim-treesitter rewrite)
      vim.api.nvim_create_autocmd("FileType", {
        pattern = ensure_installed,
        callback = function(ev)
          local ft = ev.match

          -- Enable Treesitter highlighting
          pcall(vim.treesitter.start, ev.buf, ft)

          -- Enable Treesitter indentation (disabled for web frontends)
          local disable_indent = { "html", "htmlangular", "angular", "javascript", "typescript", "tsx", "kotlin" }
          if not vim.list_contains(disable_indent, ft) then
            vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end,
  },
}
