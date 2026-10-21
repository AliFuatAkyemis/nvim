return {
  "nvim-telescope/telescope.nvim",
  tag = "0.1.8",
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = {
    defaults = {
      mappings = {
        i = require("config.prompt_keys").mappings(),
      },
    },
    pickers = {
      find_files = {
        no_ignore = true,
      },
    },
  },
}
