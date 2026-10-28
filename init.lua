-- Set leader before anything else
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Load the core configurations
require("config.options")

-- Hide Roslyn's unused-private-member warning for Unity message methods only
require("config.unity_diagnostics").setup()

-- Load the plugin manager (Lazy)
require("config.lazy")

-- Load keymappings after plugins to ensure dependencies like Telescope are available
require("config.keymaps")

-- Drop leftover [No Name] buffers once a real file is open
require("config.empty_buffer").setup()

-- New file skeletons (BufNewFile)
require("config.templates")

-- Single comment toggle key (gc)
require("config.comments").setup()
