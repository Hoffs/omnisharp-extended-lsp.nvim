# omnisharp-extended-lsp.nvim

Extended `textDocument/definition` handler that handles assembly/decompilation
loading for `$metadata$` documents.

## How it works

By providing an alternate handler for `textDocument/definition` the plugin listens
to all responses and if it receives URI with `$metadata$` it will call custom
omnisharp endpoint `o#/metadata` which returns full document source. This source
is then loaded as a scratch buffer with name set to `/$metadata$/..`. This allows
then allows jumping to the buffer based on name or from quickfix list, because it's
loaded.

Definitions from within `$metadata$` documents also work, though require 1 more
additional request per definition, [since as it is right now, `textDocument/definition`
doesn't properly return results when called from `$metadata$` document](https://github.com/OmniSharp/omnisharp-roslyn/issues/2238).
Because of that, this plugin additionally on response checks if request was made from `$metadata$` and
does another request to `o#/v2/gotodefinition` which works properly. Response from this
is handled as as described above.

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

### Telescope

This handler can also be used for [nvim-telescope](https://github.com/nvim-telescope/telescope.nvim):

```vimscript
nnoremap gd <cmd>lua require('omnisharp_extended').telescope_lsp_definitions()<cr>
```

## Important notes

- !! Plugin searches for LSP server configured with the name `omnisharp`, so if your server is configured using a different name, this will not work out of the box.
