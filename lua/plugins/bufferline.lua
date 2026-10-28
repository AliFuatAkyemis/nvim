return {
  {
    "akinsho/bufferline.nvim",
    version = "*",
    dependencies = "nvim-tree/nvim-web-devicons",
    opts = {
      options = {
        mode = "buffers",
        separator_style = "slant",
        show_buffer_close_icons = true,
        show_close_icon = true,
        diagnostics = "nvim_lsp",
        always_show_bufferline = true,
        custom_filter = function(buf)
          return require("config.empty_buffer").is_bufferline_visible(buf)
        end,
      },
    },
  },
}
