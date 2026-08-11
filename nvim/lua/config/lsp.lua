-- Blink-cmp integration
local capabilities = require("blink.cmp").get_lsp_capabilities()

-- Global defaults for all LSP servers
vim.lsp.config('*', {
  capabilities = capabilities,
  root_markers = { '.git' },
})

-- Python: Pyright
vim.lsp.config('pyright', {
  settings = {
    python = {
      analysis = {
        typeCheckingMode = "strict",
        autoSearchPaths = true,
        useLibraryCodeForTypes = true,
      },
    },
  },
})
vim.lsp.enable('pyright')

-- Rust: rust-analyzer
vim.lsp.config('rust_analyzer', {
  settings = {
    ["rust-analyzer"] = {
      checkOnSave = { command = "clippy" },
      cargo = { allFeatures = true },
      inlayHints = { enable = true },
    },
  },
})
vim.lsp.enable('rust_analyzer')

-- Nix: nixd
vim.lsp.config('nixd', {
  settings = {
    nixd = {
      formatting = { command = { "alejandra" } },
    },
  },
})
vim.lsp.enable('nixd')

-- Lua: lua_ls (using nvim-lspconfig defaults + overrides)
-- Get the default config from nvim-lspconfig and merge with our settings
local lua_ls_config = vim.lsp.config.lua_ls or {}
vim.lsp.config('lua_ls', {
  settings = {
    Lua = {
      runtime = { version = "LuaJIT" },
      workspace = { checkThirdParty = false },
      telemetry = { enable = false },
    },
  },
})
vim.lsp.enable('lua_ls')

-- Harper (grammar)
vim.lsp.config('harper_ls', {
  filetypes = { "markdown", "text", "gitcommit", "rst", "asciidoc", "norg" },
  settings = {
    ["harper-ls"] = {
      linters = {
        spell_check = true,
        spelled_numbers = false,
        an_a = true,
        sentence_capitalization = true,
        no_oxford_comma = false,
        long_sentences = true,
        repeated_words = true,
        spaces = true,
        matcher = true,
      },
    },
  },
})
vim.lsp.enable('harper_ls')

-- LTeX (LanguageTool)
vim.lsp.config('ltex', {
  filetypes = { "markdown", "tex", "rst" },
  settings = {
    ltex = {
      language = "en-US",
      diagnosticSeverity = "information",
      additionalRules = {
        enablePickyRules = true,
        motherTongue = "en",
      },
      disabledRules = {
        ["en-US"] = { "WHITESPACE_RULE", "EN_QUOTES" },
      },
      dictionary = { ["en-US"] = {} },
      hiddenFalsePositives = {},
    },
  },
})
vim.lsp.enable('ltex')

