local M = {}

local bl = require("bufferline")
bl.setup {
    options = {
        numbers = "ordinal",
        offsets = {
            {
                filetype = "fern",
                text = "File Explorer",
                highlight = "Directory",
                text_align = "center"
            },
            {
                filetype = "NvimTree",
                text = "File Explorer",
                highlight = "Directory",
                text_align = "center"
            },
            {
                filetype = "undotree",
                text = "undotree",
                highlight = "Directory",
                text_align = "center"
            },
            {
                filetype = "vista",
                text = "vista",
                highlight = "Directory",
                text_align = "center"
            }
        },
        max_name_length = 12,
    }
}

return M
