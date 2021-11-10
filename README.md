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

Since some functionality is missing in 0.5.1 heres a table with provided
functions and for which versions they can be used:

| Command  | Neovim 0.5.1 | Neovim Nightly |
| ------------- | ------------- | ------------- |
| vim.lsp.buf.definition() with updated global handlers  | Not working  | OK |
| require('omnisharp_extended').lsp_definitions()  | OK  | OK (but unnecessary) |
| require('omnisharp_extended').telescope_lsp_definitions()  | OK  | OK |

See below for instructions based on version.

### For Neovim **nightly**

To use this plugin all that needs to be done is for the nvim lsp handler for
`textDocument/definition` be overriden with one provided by this plugin.

If using `lspconfig` this can be done like this:

First configure omnisharp as per [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig/blob/master/CONFIG.md#omnisharp).

Then to that config add `handlers` with custom handler from this plugin.

```lua
local pid = vim.fn.getpid()
-- On linux/darwin if using a release build, otherwise under scripts/OmniSharp(.Core)(.cmd)
local omnisharp_bin = "/path/to/omnisharp-repo/run"
-- on Windows
-- local omnisharp_bin = "/path/to/omnisharp/OmniSharp.exe"

local config = {
  handlers = {
    ["textDocument/definition"] = require('omnisharp_extended').handler,
  },
  cmd = { omnisharp_bin, '--languageserver' , '--hostPID', tostring(pid) },
  -- rest of your settings
}

require'lspconfig'.omnisharp.setup(config)
```

### For Neovim 0.5.1

Due to the fact that in 0.5.1 request params are not available is handler
response a function to go to definitions has to be invoked manually. One option is to use
telescope method explained in the next section or to use `lsp_definitions()` function which
mimics standard definitions behavior.

```vimscript
nnoremap gd <cmd>lua require('omnisharp_extended').lsp_definitions()<cr>
```

### Telescope

This handler can also be used for [nvim-telescope](https://github.com/nvim-telescope/telescope.nvim):

```vimscript
nnoremap gd <cmd>lua require('omnisharp_extended').telescope_lsp_definitions()<cr>
```

## Important notes

- !! Plugin searches for LSP server configured with the name `omnisharp`, so if your server is configured using a different name, this will not work out of the box.
