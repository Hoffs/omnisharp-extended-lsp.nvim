# omnisharp-extended-lsp.nvim

Extended LSP handlers and additional commands that support and are aware of OmniSharp `$metadata` documents (e.g. decompilation) and source generated documents.

Currently supported commands:
- `textDocument/definition`
- `textDocument/typeDefinition`
- `textDocument/references`
- `textDocument/implementation`

Related issue on `$metadata` documents: https://github.com/OmniSharp/omnisharp-roslyn/issues/2238

## How to use

There are 2 ways to use the plugin, using custom command or overriding lsp handler.

(tested with Neovim 0.9.5 on Windows and 0.10.0 nightly on MacOS)

### Custom command (*Optimal*)

Using provided custom command for each supported action:

```vim
-- replaces vim.lsp.buf.definition()
nnoremap gd <cmd>lua require('omnisharp_extended').lsp_definition()<cr>

-- replaces vim.lsp.buf.type_definition()
nnoremap <leader>D <cmd>lua require('omnisharp_extended').lsp_type_definition()<cr>

-- replaces vim.lsp.buf.references()
nnoremap gr <cmd>lua require('omnisharp_extended').lsp_references()<cr>

-- replaces vim.lsp.buf.implementation()
nnoremap gi <cmd>lua require('omnisharp_extended').lsp_implementation()<cr>
```

These commands will call appropriate OmniSharp provided LSP command directly (e.g. `o#/v2/gotodefinition` instead of `textDocument/definition`). OmniSharp commands provide information about metadata files (decompiled assemblies and such) and source generated files. If results contain any of these files, the handler will then try to create read-only buffers before bringing up quickfix list or navigating to single result.

#### Custom command for Telescope

There are also commands provided specifically for [nvim-telescope](https://github.com/nvim-telescope/telescope.nvim) users:

```vim
nnoremap gr <cmd>lua require('omnisharp_extended').telescope_lsp_references()<cr>
-- options are supported as well
nnoremap gd <cmd>lua require('omnisharp_extended').telescope_lsp_definition({ jump_type = "vsplit" })<cr>
nnoremap <leader>D <cmd>lua require('omnisharp_extended').telescope_lsp_type_definition()<cr>
nnoremap gi <cmd>lua require('omnisharp_extended').telescope_lsp_implementation()<cr>
```

You can also pass in the `excludeDefinition` option which does the equivalent of the `include_declaration` telescope setting.

```lua
vim.keymap.set(
  "n",
  "gr",
  function() require("omnisharp_extended").telescope_lsp_references(require("telescope.themes").get_ivy({ excludeDefinition = true })) end,
  { noremap = true }
)
vim.keymap.set("n", "gd", require("omnisharp_extended").telescope_lsp_definition, { noremap = true })
vim.keymap.set("n", "<leader>D", function() require("omnisharp_extended").telescope_lsp_references() end, { noremap = true })
vim.keymap.set("n", "gi", require("omnisharp_extended").telescope_lsp_implementation, { noremap = true })
```

### Custom handler (*Suboptimal*)

Using provided custom LSP handler for each supported action:

```lua
local config = {
  ...
  handlers = {
    ["textDocument/definition"] = require('omnisharp_extended').definition_handler,
    ["textDocument/typeDefinition"] = require('omnisharp_extended').type_definition_handler,
    ["textDocument/references"] = require('omnisharp_extended').references_handler,
    ["textDocument/implementation"] = require('omnisharp_extended').implementation_handler,
  },
  ...
}

require'lspconfig'.omnisharp.setup(config)
```

Custom handler is invoked for results of respective LSP native command (e.g. `vim.lsp.buf.definition()`). The handler then checks the results and if it determines that the result may contain non-local files (metadata, source generated) or that the request was made from within metadata file, it will retry the request using `Custom command` method, mentioned above. This means, that in some cases, LSP will be called twice, compared to always once, when using a command approach (not counting when there is a need to retrieve metadata/source generated file contents).

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

## Important notes

- Plugin searches for LSP server configured with the name `omnisharp` or `omnisharp_mono`, so if your server is configured using a different name, this will not work out of the box.
- Navigation from within source generated files does not seem to be supported by omnisharp itself. Source generated files are technically identified by 2 UUID's, but gotodefinition expects a file name, so technically these 2 can't map to each other. Maybe in the future omnisharp devs will think of a way to make this work.
- Telescope preview does not work for "special" files as they are not actually accessible files. It should be possible to modify `buffer_previewer_maker` to handle this, but currently has not been implemented.
