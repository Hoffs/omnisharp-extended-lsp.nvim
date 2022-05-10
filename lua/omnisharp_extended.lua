local utils = require('omnisharp_extended/utils')
local make_entry = require "telescope.make_entry"

local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local conf = require("telescope.config").values

local M = {}

M.defolderize = function(str)
-- private static string Folderize(string path) => string.Join("/", path.Split('.'));
  return string.gsub(str, '[/\\]', '.')
end

M.matcher = '%$metadata%$[/\\]Project[/\\](.*)[/\\]Assembly[/\\](.*)[/\\]Symbol[/\\](.*).cs$'
M.matcher_meta_uri = '(%$metadata%$[/\\].*)$'

M.parse_meta_uri = function(uri)
  local found, _, project, assembly, symbol = string.find(uri, M.matcher)

  if found then
    return found, M.defolderize(project), M.defolderize(assembly), M.defolderize(symbol)
  end
end

M.get_omnisharp_client = function()
  local clients = vim.lsp.buf_get_clients(0)
  for _, client in pairs(clients) do
    if client.name == "omnisharp" then
      return client
    end
  end
end

M.buf_from_metadata = function(result, client_id)
  local normalized = string.gsub(result.Source, '\r\n', '\n')
  local source_lines = utils.split(normalized, '\n')

  -- normalize backwards slash to forwards slash
  local normalized_source_name = string.gsub(result.SourceName, '\\', '/')
  local file_name = '/' .. normalized_source_name

  -- this will be /$metadata$/...
  local bufnr = utils.get_or_create_buf(file_name)
  -- TODO: check if bufnr == 0 -> error
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)
  vim.api.nvim_buf_set_option(bufnr, 'readonly', false)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, source_lines)
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
  vim.api.nvim_buf_set_option(bufnr, 'readonly', true)
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'cs')
  vim.api.nvim_buf_set_option(bufnr, 'modified', false)

  -- attach lsp client ??
  vim.lsp.buf_attach_client(bufnr, client_id)

  -- vim.api.nvim_win_set_buf(0, bufnr)

  -- set_cursor is (1, 0) indexed, where LSP range is 0 indexed, so add 1 to line number
  -- vim.api.nvim_win_set_cursor(0, { range.start.line+1, range.start.character })
  --
  return bufnr, file_name
end

-- Gets metadata for all locations with $metadata$
-- Returns: boolean whether any requests were made
M.get_metadata = function(locations)
  local client = M.get_omnisharp_client()
  if not client then
    -- TODO: Error?
    return false
  end

  local fetched = {}
  for _, loc in pairs(locations) do
    local uri = utils.urldecode(loc.uri)
    local is_meta, project, assembly, symbol = M.parse_meta_uri(uri)

    if is_meta then
      local params = {
        timeout = 5000,
        assemblyName = assembly,
        projectName = project,
        typeName = symbol,
      }

      -- request_sync?
      -- if async, need to trigger when all are finished
      local result, err = client.request_sync('o#/metadata', params, 10000)
      if not err then
        local bufnr, name = M.buf_from_metadata(result.result, client.id)
        -- change location name to the one returned from metadata
        -- alternative is to open buffer under location uri
        -- not sure which one is better
        loc.uri = 'file://' .. name
        fetched[loc.uri] = {
          bufnr = bufnr,
          range = loc.range,
        }
      end
    end
  end

  return fetched
end

M.definitions_to_locations = function(definitions)
  -- translate definitions to locations
  -- https://github.com/OmniSharp/omnisharp-roslyn/blob/master/src/OmniSharp.LanguageServerProtocol/Handlers/OmniSharpDefinitionHandler.cs#L44
  if definitions == nil then
    return nil
  end

  local locations = {}
  for _, definition in pairs(definitions) do
    local range = {}
    range['start'] = {
      line = definition.Location.Range.Start.Line,
      character = definition.Location.Range.Start.Column,
    }
    range['end'] = {
      line = definition.Location.Range.End.Line,
      character = definition.Location.Range.End.Column,
    }

    local location = {
      uri = string.gsub(definition.Location.FileName, '^%$metadata%$', 'file:///$metadata$'),
      range = range
    }

    table.insert(locations, location)
  end

  return locations
end

M.textdocument_definition_to_locations = function(result)
  if not vim.tbl_islist(result) then
    return { result }
  end

  return result
end

M.handle_locations = function(locations, offset_encoding)
  local fetched = M.get_metadata(locations)

  if not vim.tbl_isempty(fetched) then
    if #locations > 1 then
      utils.set_qflist_locations(locations, offset_encoding)
      vim.api.nvim_command("copen")
      return true
    else
      -- utils.jump_to_location(locations[1], fetched[locations[1].uri].bufnr)
      vim.lsp.util.jump_to_location(locations[1], offset_encoding)
      return true
    end
  else
    return false
  end
end

M.handler = function(err, result, ctx, config)
  -- If definition request is made from meta document, then it SHOULD
  -- always return no results.
  local client = M.get_omnisharp_client()
  local req_from_meta = M.parse_meta_uri(ctx.params.textDocument.uri)
  if req_from_meta then
    -- if request was from metadata document,
    -- repeat it with /gotodefinition since that supports metadata
    -- documents properly ( https://github.com/OmniSharp/omnisharp-roslyn/issues/2238 )

    -- use regex to get file uri. On windows there might be extra path things added before $metadata$ due to path semantics.
    local found, _, file_uri = string.find(ctx.params.textDocument.uri, M.matcher_meta_uri)
    if not found then
      return
    end

    local params = {
      fileName = file_uri,
      column = ctx.params.position.character,
      line = ctx.params.position.line,
    }

    if client then
      local result, err = client.request_sync('o#/v2/gotodefinition', params, 10000)
      if err then
        vim.api.nvim_err_writeln('Error when executing ' .. 'o#/v2/gotodefinition' .. ' : ' .. err)
        return
      end

      local locations = M.definitions_to_locations(result.result.Definitions)
      local handled = M.handle_locations(locations, client.offset_encoding)
      if not handled then
        return vim.lsp.handlers['textDocument/definition'](err, result, ctx, config)
      end
    end
  end

  local locations = M.textdocument_definition_to_locations(result)
  local handled = M.handle_locations(locations, client.offset_encoding)
  if not handled then
    return vim.lsp.handlers['textDocument/definition'](err, result, ctx, config)
  end
end

M.handle_locations_telescope = function(locations, offset_encoding, opts)
  opts = opts or {}

  local fetched = M.get_metadata(locations)
  if #locations == 0 then
    return
  elseif #locations == 1 and opts.jump_type ~= "never" then
    if opts.jump_type == "tab" then
      vim.cmd "tabedit"
    elseif opts.jump_type == "split" then
      vim.cmd "new"
    elseif opts.jump_type == "vsplit" then
      vim.cmd "vnew"
    end
    vim.lsp.util.jump_to_location(locations[1], offset_encoding)
  else
    locations = vim.lsp.util.locations_to_items(locations, offset_encoding)
    pickers.new(opts, {
      prompt_title = "LSP Definitions",
      finder = finders.new_table {
        results = locations,
        entry_maker = opts.entry_maker or make_entry.gen_from_quickfix(opts),
      },
      previewer = conf.qflist_previewer(opts),
      sorter = conf.generic_sorter(opts),
    }):find()
  end
end

M.handler_telescope = function(err, result, ctx, _)
  -- If definition request is made from meta document, then it SHOULD
  -- always return no results.
  local client = M.get_omnisharp_client()
  local req_from_meta = M.parse_meta_uri(ctx.params.textDocument.uri)
  if req_from_meta then
    -- if request was from metadata document,
    -- repeat it with /gotodefinition since that supports metadata
    -- documents properly ( https://github.com/OmniSharp/omnisharp-roslyn/issues/2238 )

    -- use regex to get file uri. On windows there might be extra path things added before $metadata$ due to path semantics.
    local found, _, file_uri = string.find(ctx.params.textDocument.uri, M.matcher_meta_uri)
    if not found then
      return
    end

    local params = {
      fileName = file_uri,
      column = ctx.params.position.character,
      line = ctx.params.position.line,
    }

    if client then
      local result, err = client.request_sync('o#/v2/gotodefinition', params, 10000)
      if err then
        vim.api.nvim_err_writeln('Error when executing ' .. 'o#/v2/gotodefinition' .. ' : ' .. err)
        return
      end

      local locations = M.definitions_to_locations(result.result.Definitions)
      M.handle_locations_telescope(locations, client.offset_encoding)
    end
  end

  local locations = M.textdocument_definition_to_locations(result)
  M.handle_locations_telescope(locations, client.offset_encoding)
end

M.telescope_lsp_definitions = function()
  local client = M.get_omnisharp_client()
  if client then
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)

    local handler = function(err, result, ctx, config)
      ctx.params = params
      M.handler_telescope(err, result, ctx, config)
    end

    client.request('textDocument/definition', params, handler)
  end
end

M.lsp_definitions = function()
  local client = M.get_omnisharp_client()
  if client then
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)

    local handler = function(err, result, ctx, config)
      ctx.params = params
      M.handler(err, result, ctx, config)
    end

    client.request('textDocument/definition', params, handler)
  end
end

return M
