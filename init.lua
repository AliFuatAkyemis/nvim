-- Set leader before anything else
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Load the core configurations
require("config.options")

-- Load the plugin manager (Lazy)
require("config.lazy")

-- Load keymappings after plugins to ensure dependencies like Telescope are available
require("config.keymaps")
