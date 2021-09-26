# omnisharp-extended-lsp.nvim

Extended `textDocument/definition` handler that handles assembly/decompilation
loading for `$metadata$` documents.

## Usage

To use this plugin all that needs to be done is for the nvim lsp handler for
`textDocument/definition` be overriden with one provided by this plugin.

If using `lspconfig` this can be done like this:

```lua
local config = {
  handlers = {
    ["textDocument/definition"] = require('omnisharp_extended').handler,
  },
  cmd = { run_path, '--languageserver' , '--hostPID', tostring(pid) },
  -- rest of your settings
}

require'lspconfig'.omnisharp.setup(config)
```

## Important notes

- !! Plugin searches for LSP server configured with the name `omnisharp`, so if your server is configured using a different name, this will not work out of the box.
