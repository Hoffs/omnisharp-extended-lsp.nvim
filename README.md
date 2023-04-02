# omnisharp-extended-lsp.nvim

Extended `textDocument/definition` and `textDocument/references` handler/command that handles assembly/decompilation loading for `$metadata$` and source generated documents.

## How it works

There are 2 ways to use the plugin, using custom command or overriding lsp handler.

### Custom command (*Optimal*)

Using `require('omnisharp_extended').lsp_definitions()` instead of `vim.lsp.buf.definition()`.

This will call omnisharp lsp using `o#/v2/gotodefinition` command instead of standard `textDocument/definition` command. Omnisharp command natively provides information about metadata files (decompiled assemblies and such) and source generated files. If results contain any of these files, the handler will then try to create read-only buffers before bringing up quickfix list or navigating to single result.

Using `require('omnisharp_extended').lsp_references()` instead of `vim.lsp.buf.references()`.

References replacement works in similar fashion as well. It will call `o#/findusages` command instead of standard `textDocument/references` command. It also provides information about source generated files, so if such file is encountered, it will be loaded before selection is shown.

### Custom handler (*Suboptimal*)

Using custom lsp handler `require('omnisharp_extended').handler` when configuring lsp for `textDocument/definition` or `require('omnisharp_extended').references_handler` for `textDocument/references`.

Custom handler is invoked for results of `vim.lsp.buf.definition()` commands. The handler then checks the results and if it determines that the result may contain "special" files (metadata, source genereated) or that request was made from within metadata file, it will retry the request using `Custom command` method, as explained above. Meaning that in certain cases, this will do more than 1 definition request to lsp server.

References handler works in identical manner.

Related issue: https://github.com/OmniSharp/omnisharp-roslyn/issues/2238

## Usage

Tested with Neovim 0.8.3

### OmniSharp settings

For decompilation to work, OmniSharp extension for decompilation support might need to be enabled.
See [omnisharp wiki](https://github.com/OmniSharp/omnisharp-roslyn/wiki/Configuration-Options) for
information where `omnisharp.json` needs to be placed (`~/.omnisharp/omnisharp.json`).

```json
{
  "RoslynExtensionsOptions": {
    "enableDecompilationSupport": true
  }
}
```

### Custom command setup

Simply setup a desired keymap to invoke definition command:

```vimscript
nnoremap gd <cmd>lua require('omnisharp_extended').lsp_definitions()<cr>
nnoremap gr <cmd>lua require('omnisharp_extended').lsp_references()<cr>
```

### Custom handler setup

To use this plugin with custom lsp handler, `textDocument/definition` or `textDocument/references` handler has to be overriden with the one provided by this plugin.

First configure omnisharp as per [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md#omnisharp).

Then to that config add `handlers` with custom handler from this plugin:

```lua
local pid = vim.fn.getpid()
-- On linux/darwin if using a release build, otherwise under scripts/OmniSharp(.Core)(.cmd)
local omnisharp_bin = "/path/to/omnisharp-repo/run"
-- on Windows
-- local omnisharp_bin = "/path/to/omnisharp/OmniSharp.exe"

local config = {
  handlers = {
    ["textDocument/definition"] = require('omnisharp_extended').handler,
    ["textDocument/references"] = require('omnisharp_extended').references_handler,
  },
  cmd = { omnisharp_bin, '--languageserver' , '--hostPID', tostring(pid) },
  -- rest of your settings
}

require'lspconfig'.omnisharp.setup(config)
```

### Telescope

This handler can also be used for [nvim-telescope](https://github.com/nvim-telescope/telescope.nvim):

```vimscript
nnoremap gd <cmd>lua require('omnisharp_extended').telescope_lsp_definitions()<cr>
nnoremap gr <cmd>lua require('omnisharp_extended').telescope_lsp_references()<cr>
```

## Important notes

- Plugin searches for LSP server configured with the name `omnisharp` or `omnisharp_mono`, so if your server is configured using a different name, this will not work out of the box.
- Navigation from within source generated files does not seem to be supported by omnisharp itself. Source generated files are technically identified by 2 UUID's, but gotodefinition expects a file name, so technically these 2 can't map to each other. Maybe in the future omnisharp devs will think of a way to make this work.
- Telescope preview does not work for "special" files as they are not actually accessible files. It should be possible to modify `buffer_previewer_maker` to handle this, but currently out of scope.
