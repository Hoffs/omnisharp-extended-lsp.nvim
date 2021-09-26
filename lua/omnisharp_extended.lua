local log = require('omnisharp_extended/log')
local utils = require('omnisharp_extended/utils')

local M = {}

M.defolderize = function(str)
-- private static string Folderize(string path) => string.Join("/", path.Split('.'));
  return string.gsub(str, '/', '.')
end

M.matcher = '%$metadata%$/Project/(.*)/Assembly/(.*)/Symbol/(.*).cs$'

M.parse_meta_uri = function(uri)
  local found, _, project, assembly, symbol = string.find(uri, M.matcher)

  if found then
    return found, M.defolderize(project), M.defolderize(assembly), M.defolderize(symbol)
  end

  return
end

M.get_omnisharp_client = function()
  local clients = vim.lsp.buf_get_clients(0)
  for id, client in pairs(clients) do
    if client.name == "omnisharp" then
      return client
    end
  end

  return
end

M.on_metadata = function(error, result, ctx, config, range)
  if error then
    return
  end

  local normalized = string.gsub(result.Source, '\r\n', '\n')
  local source_lines = utils.split(normalized, '\n')

  -- this will be /$metadata$/...
  local bufnr = utils.get_or_create_buf('/' .. result.SourceName)
  -- TODO: check if bufnr == 0 -> error
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, source_lines)
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'cs')

  -- attach lsp client
  vim.lsp.buf_attach_client(bufnr, ctx.client_id)

  -- vim.api.nvim_win_set_buf(0, bufnr)

  -- set_cursor is (1, 0) indexed, where LSP range is 0 indexed, so add 1 to line number
  -- vim.api.nvim_win_set_cursor(0, { range.start.line+1, range.start.character })
end

M.make_on_metadata = function(range)
  return function(error, result, ctx, config)
    M.on_metadata(error, result, ctx, config, range)
  end
end

-- Gets metadata for all locations with $metadata$
-- Returns: boolean whether any requests were made
M.get_metadata = function(locations)
  local client = M.get_omnisharp_client()
  if not client then
    -- TODO: Error?
    return false
  end

  local required_metadata = false
  for _, loc in pairs(locations) do
    local uri = utils.urldecode(loc.uri)
    local is_meta, project, assembly, symbol = M.parse_meta_uri(uri)

    if is_meta then
      required_metadata = true
      local params = {
        timeout = 5000,
        assemblyName = assembly,
        projectName = project,
        typeName = symbol,
      }

      -- request_sync?
      -- if async, need to trigger when all are finished
      client.request('o#/metadata', params, M.make_on_metadata(loc.range))
    end
  end

  return required_metadata
end

M.on_gotodefinition = function(error, result, ctx, config)
  -- translate definitions to locations
  -- https://github.com/OmniSharp/omnisharp-roslyn/blob/master/src/OmniSharp.LanguageServerProtocol/Handlers/OmniSharpDefinitionHandler.cs#L44
  if result.Definitions == nil then
    return vim.NIL
  end

  local locations = {}
  for i, definition in pairs(result.Definitions) do
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
      uri = definition.Location.FileName,
      range = range
    }

    table.insert(locations, location)
  end


  M.get_metadata(locations)
end

M.textdocument_definition_to_locations = function(result)
  if not vim.tbl_islist(result) then
    return { result }
  end

  return result
end

M.handler = function(err, result, ctx, config)
  -- If definition request is made from meta document, then it SHOULD
  -- always return no results.
  local req_from_meta = M.parse_meta_uri(ctx.params.textDocument.uri)
  if result.uri == nil and req_from_meta then
    -- if request was from metadata document,
    -- repeat it with /gotodefinition since that supports metadata
    -- documents properly ( https://github.com/OmniSharp/omnisharp-roslyn/issues/2238 )
    local params = {
      fileName = string.gsub(ctx.params.textDocument.uri, 'file:///', ''),
      column = ctx.params.position.character,
      line = ctx.params.position.line,
    }

    local client = M.get_omnisharp_client()
    if client then
      client.request('o#/v2/gotodefinition', params, M.on_gotodefinition)
    end

    return vim.NIL
  end

  local locations = M.textdocument_definition_to_locations(result)

  local passthrough

  local fetching_metadata = M.get_metadata(locations)

  if fetching_metadata then
    return vim.NIL
  else
    return vim.lsp.handlers['textDocument/definition'](err, result, ctx, config)
  end
end

return M
