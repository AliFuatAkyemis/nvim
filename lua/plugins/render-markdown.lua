-- render-markdown.nvim is maintained as a local fork so it can carry a small
-- downstream patch that lazy.nvim would otherwise refuse to update (dirty
-- working tree):
--
--   lua/render-markdown/render/markdown/quote.lua
--     Inline math on a callout title line (...) is rendered inside the title
--     overlay instead of being swallowed by it (upstream issue #305).
--   lua/render-markdown/handler/latex.lua
--     Exposes the latex conversion cache via get_converted() for reuse.
--
-- Update the fork with:
--   git -C ~/dev/render-markdown.nvim pull --rebase
-- (Fast-forwards upstream main and keeps the patch on top. If the patched
-- code changed upstream a conflict appears that needs a manual merge.)
return {
  dir = vim.fn.expand("~/dev/render-markdown.nvim"),
  name = "render-markdown.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
  ft = { "markdown", "opencode_output" },
  opts = {
    render_modes = { "n", "c" },
    file_types = { "markdown", "opencode_output" },
    latex = {
      enabled = true,
      converter = "latex2text",
    },
    anti_conceal = {
      enabled = false,
    },
  },
  config = function(_, opts)
    require("render-markdown").setup(opts)
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "markdown", "opencode_output" },
      callback = function()
        vim.opt_local.conceallevel = 2
      end,
    })
  end,
}
