vim.o.completeopt = "menu,preview,noinsert"
require'compe'.setup {
    preselect = 'always';
    enabled = true;
    autocomplete = true;
    debug = false;
    min_length = 1;
    throttle_time = 80;
    source_timeout = 100;
    resolve_timeout = 400;
    incomplete_delay = 50;
    max_abbr_width = 100;
    max_kind_width = 100;
    max_menu_width = 100;
    documentation = {
        border = { '', '' ,'', ' ', '', '', '', ' ' }, -- the border option is the same as `|help nvim_open_win|`
        winhighlight = "NormalFloat:CompeDocumentation,FloatBorder:CompeDocumentationBorder",
        max_width = 120,
        min_width = 60,
        max_height = math.floor(vim.o.lines * 0.2),
        min_height = 1,
    };

    source = {
        path = true;
        buffer = true;
        calc = true;
        nvim_lsp = true;
        nvim_lua = true;
        vsnip = true;
        ultisnips = true;
        luasnip = true;
    };
}
