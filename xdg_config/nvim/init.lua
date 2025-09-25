-- ====== OPTIONS ======
vim.loader.enable()
vim.g.mapleader = " "
vim.opt.title = true
vim.opt.termguicolors = true -- ターミナルの色を24ビットカラーに設定
vim.opt.completeopt = { "menuone", "noselect" } -- 補完メニューを表示し、自動で選択しない
vim.opt.ignorecase = true -- 検索時に大文字小文字を区別しない
vim.opt.pumheight = 10 -- ポップアップメニューの高さを10行に設定
vim.opt.showtabline = 2 -- タブラインを常に表示
vim.opt.smartcase = true -- 検索パターンに大文字が含まれている場合は大文字小文字を区別
vim.opt.smartindent = true -- 自動インデントを有効に
vim.opt.swapfile = false -- スワップファイルを作成しないように
vim.opt.undofile = true -- アンドゥ情報をファイルに保存
vim.opt.writebackup = false -- 書き込み時のバックアップファイルを作成しないように
vim.opt.expandtab = true -- タブをスペースに展開
vim.opt.cursorline = true -- カーソル行をハイライト
vim.opt.number = true -- 行番号を表示
vim.opt.wrap = false -- 折り返しを無効に
vim.opt.scrolloff = 8 -- スクロール時に画面の端から8行分余裕を持たせる
vim.opt.sidescrolloff = 8 -- スクロール時に画面の端から8列分余裕を持たせる
vim.opt.laststatus = 3 -- ステータスラインを常に表示し、現在のウィンドウだけでなく全てのウィンドウに適用
vim.opt.list = true -- 制御文字を表示

-- ====== CLIPBOARD ======
vim.opt.clipboard = "unnamedplus"
local osc52 = require("vim.ui.clipboard.osc52")
local function paste(_)
  return vim.split(vim.fn.getreg('"'), "\n")
end
vim.g.clipboard = {
  copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
  paste = { ["+"] = paste, ["*"] = paste },
}

-- ====== KEYMAP ======
vim.keymap.set("i", "jk", "<ESC>")
vim.keymap.set("t", "fd", [[<C-\><C-n>]]) -- Terminal Mode 時fdでノーマルモードに戻る
vim.keymap.set("x", "<M-k>", ":move '<-2<CR>gv=gv") -- 選択範囲を上に移動
vim.keymap.set("x", "<M-j>", ":move '>+1<CR>gv=gv") -- 選択範囲を下に移動

-- ====== COLORS ======
vim.api.nvim_set_hl(0, "Function", { fg = "NvimLightBlue" })
vim.api.nvim_set_hl(0, "Identifier", { fg = "NvimLightBlue" })
vim.api.nvim_set_hl(0, "Constant", { fg = "NvimLightCyan" })
vim.api.nvim_set_hl(0, "Statement", { fg = "NvimLightBlue", bold = true })
vim.api.nvim_set_hl(0, "Special", { link = "Constant" })
vim.api.nvim_set_hl(0, "@string.documentation", { fg = "NvimLightGreen", bold = true })
vim.api.nvim_set_hl(0, "@variable.parameter", { fg = "NvimLightCyan", italic = true })
vim.api.nvim_set_hl(0, "IblScope", { fg = "NvimLightBlue" })

-- ====== PLUGIN ======
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
local lazyrepo = "https://github.com/folke/lazy.nvim.git"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  {
    "akinsho/bufferline.nvim",
    event = "BufRead",
    opts = {
      options = {
        diagnostics = "nvim_lsp",
        diagnostics_indicator = function(_, _, diag)
          local ret = (diag.error and " " .. diag.error .. " " or "") .. (diag.warning and " " .. diag.warning or "")
        return vim.trim(ret)
      end,
      },
    }
  },
  {
    'saghen/blink.cmp',
    version = '*',
    opts = {
      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 100 },
        list = { selection = { preselect = false, auto_insert = true } },
      },
      signature = { enabled = true }
    }
  },
  { "github/copilot.vim", event = "BufRead" },
  {
    "folke/flash.nvim",
    keys = {
      { "s", mode = { "n", "x", "o" }, "<cmd>lua require('flash').jump()<cr>" },
      { "S", mode = { "n", "x", "o" }, "<cmd>lua require('flash').treesitter()<cr>" },
    },
  },
  {
    "lewis6991/gitsigns.nvim",
    dependencies = { "petertriho/nvim-scrollbar" },
    event = "BufReadPre",
    keys = {
      { "<leader>hd", mode = "n", "<cmd>Gitsigns diffthis<cr>" },
      { "<leader>hp", mode = "n", "<cmd>Gitsigns preview_hunk<cr>" },
    },
    config = function()
      require("gitsigns").setup()
      require("scrollbar").setup()
      require("scrollbar.handlers.gitsigns").setup()
    end,
  },
  { "nvim-lualine/lualine.nvim", dependencies = { "nvim-tree/nvim-web-devicons" }, opts = {} },
  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp", -- LSPの補完ソース
      "hrsh7th/cmp-buffer",   -- 開いているバッファ内の単語を補完
      "hrsh7th/cmp-path",     -- ファイルパスを補完
      "L3MON4D3/LuaSnip",     -- スニペットエンジン
      "saadparwaiz1/cmp_luasnip", -- nvim-cmpでLuaSnipを使えるようにする
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "buffer" },
          { name = "path" },
        }),
        mapping = cmp.mapping.preset.insert({
          ['<C-b>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<C-e>'] = cmp.mapping.abort(),
          ['<CR>'] = cmp.mapping.confirm({ select = true }), -- Enterで補完を確定
        }),
      })
    end,
  },
  {
    "williamboman/mason.nvim",
    event = "BufRead",
    dependencies = {
      "williamboman/mason-lspconfig.nvim",
      "neovim/nvim-lspconfig",
      "nvimtools/none-ls.nvim", -- null-lsの代わりにnone-lsを使用
      "jay-babu/mason-null-ls.nvim", -- none-lsのツールをmasonで管理するために使用
    },
    config = function()
      -- 共通のLSP設定を定義
      local on_attach = function(client, bufnr)
        -- ここにLSPが起動したときのキーマップなどを設定
        vim.keymap.set('n', 'K', vim.lsp.buf.hover, { buffer = bufnr, desc = 'LSP Hover' })
        vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { buffer = bufnr, desc = 'Go to Definition' })
        vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, { buffer = bufnr, desc = 'Code Action' })
      end

      -- nvim-cmpを使っている場合、補完能力(capabilities)を設定
      -- もしnvim-cmpをまだ使っていなければ、将来のためにこのままにしておくことをお勧めします
      local capabilities = require('cmp_nvim_lsp').default_capabilities()

      -- masonをセットアップ
      require("mason").setup()

      -- mason-lspconfigをセットアップ
      require("mason-lspconfig").setup({
        -- インストールしたいLSPサーバーをここに列挙
        ensure_installed = { "lua_ls", "tsserver", "gopls", "rust_analyzer" },
        -- 各LSPサーバーに共通設定を適用
        handlers = {
          function(server_name)
            require("lspconfig")[server_name].setup({
              on_attach = on_attach,    -- 上で定義した共通設定を渡す
              capabilities = capabilities, -- 補完能力を渡す
            })
          end,

          -- 特定のサーバーにだけ追加設定をしたい場合
          ["lua_ls"] = function()
            require("lspconfig").lua_ls.setup({
              on_attach = on_attach,
              capabilities = capabilities,
              settings = {
                Lua = {
                  diagnostics = {
                    globals = { "vim" },
                  },
                },
              },
            })
          end,
        },
      })

      -- none-ls (フォーマッタ、リンター) の設定
      local null_ls = require("null-ls")
      null_ls.setup({
        sources = {
          -- ここに使いたいフォーマッタやリンターを追加
          -- 例: null_ls.builtins.formatting.prettier,
          --     null_ls.builtins.diagnostics.eslint,
        },
      })

      -- mason-null-ls (現在はnone-lsにも対応) でツールの自動インストールを管理
      require("mason-null-ls").setup({
        -- none-lsのsourcesに合わせて、自動インストールしたいツールを列挙
        ensure_installed = { "prettier", "eslint_d" },
        automatic_installation = true,
      })
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    event = "BufRead",
    build = ":TSUpdate",
    main = "nvim-treesitter.configs",
    opts = { highlight = { enable = true }, indent = { enable = true } },
  },
  {
    "folke/snacks.nvim",
    lazy = false,
    keys = {
      { "<leader>ff", "<cmd>lua require('snacks').picker.files()<cr>", desc = "Find Files" },
      { "<leader>fg", "<cmd>lua require('snacks').picker.grep()<cr>", desc = "Live Grep" },
      { "<leader>n", "<cmd>lua require('snacks').explorer()<cr>", desc = "Explorer" },
    },
    opts = {
      dashboard = { enabled = true },
      indent = { enabled = true, animate = { enabled = false } },
    },
  },
  {
    "akinsho/toggleterm.nvim",
    keys = {
      { "<leader>tt", "<cmd>ToggleTerm direction=float<cr>", desc = "Toggle Terminal(Float)" },
      { "<leader>tj", "<cmd>ToggleTerm direction=horizontal<cr>", desc = "Toggle Terminal(Horizontal)" },
    },
    opts = {},
  },
  {
    "folke/trouble.nvim",
    cmd = "Trouble",
    keys = {
      { "<leader>e", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics" },
      { "gd", "<cmd>Trouble lsp toggle focus=false<cr>", desc = "LSP References" },
    },
    opts = {},
  },
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    keys = { { "<leader>?", "<cmd>WhichKey<cr>", desc = "Show Keymaps" } },
    opts = { preset = "helix", },
  },
  defaults = { lazy = true },
})


