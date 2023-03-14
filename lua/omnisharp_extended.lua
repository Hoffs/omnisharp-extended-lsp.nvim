local utils = require('omnisharp_extended/utils')

local pickers = nil
local finders = nil
local conf = nil
local telescope_exists, make_entry = pcall(require, "telescope.make_entry");
if telescope_exists then
  pickers = require "telescope.pickers"
  finders = require "telescope.finders"
  conf = require("telescope.config").values
end

--[[
OmniSharp Protocol:

o#/v2/gotodefinition
    public class GotoDefinitionRequest : Request
    {
        public int Timeout { get; set; } = 10000;
        public bool WantMetadata { get; set; }
    }

    public record GotoDefinitionResponse
    {
        public List<Definition>? Definitions { get; init; }
    }

    public record Definition
    {
        public Location Location { get; init; } = null!;
        public MetadataSource? MetadataSource { get; init; }
        public SourceGeneratedFileInfo? SourceGeneratedFileInfo { get; init; }
    }

    public record Location
    {
        public string FileName { get; init; } = null!;
        public Range Range { get; init; } = null!;
    }

    public record Range
    {
        public Point Start { get; init; }
        public Point End { get; init; }
    }

    public record Point : IEquatable<Point>
    {
        [JsonConverter(typeof(ZeroBasedIndexConverter))]
        public int Line { get; init; }
        [JsonConverter(typeof(ZeroBasedIndexConverter))]
        public int Column { get; init; }
    }

    public class MetadataSource
    {
        public string AssemblyName { get; set; }
        public string TypeName { get; set; }
        public string ProjectName { get; set; }
        public string VersionNumber { get; set; }
        public string Language { get; set; }
    }

    public record SourceGeneratedFileInfo
    {
        public Guid ProjectGuid { get; init; }
        public Guid DocumentGuid { get; init; }
    }


o#/metadata
    public class MetadataSource
    {
        public string AssemblyName { get; set; }
        public string TypeName { get; set; }
        public string ProjectName { get; set; }
        public string VersionNumber { get; set; }
        public string Language { get; set; }
    }

    public class MetadataResponse
    {
        public string SourceName { get; set; }
        public string Source { get; set; }
    }

o#/v1/findusages
    public class SimpleFileRequest : IRequest
    {
        private string _fileName;

        public string FileName
        {
            get => _fileName?.Replace(Path.AltDirectorySeparatorChar, Path.DirectorySeparatorChar);
            set => _fileName = value;
        }
    }

    public class Request : SimpleFileRequest
    {
        [JsonConverter(typeof(ZeroBasedIndexConverter))]
        public int Line { get; set; }
        [JsonConverter(typeof(ZeroBasedIndexConverter))]
        public int Column { get; set; }
        public string Buffer { get; set; }
        public IEnumerable<LinePositionSpanTextChange> Changes { get; set; }
        [JsonProperty(DefaultValueHandling = DefaultValueHandling.Populate)]
        public bool ApplyChangesTogether { get; set; }
    }

    public class FindUsagesRequest : Request
    {
        /// <summary>
        /// Only search for references in the current file
        /// </summary>
        public bool OnlyThisFile { get; set; }
        public bool ExcludeDefinition { get; set; }
    }

    public class QuickFix
    {
        public string FileName { get; set; }
        [JsonConverter(typeof(ZeroBasedIndexConverter))]
        public int Line { get; set; }
        [JsonConverter(typeof(ZeroBasedIndexConverter))]
        public int Column { get; set; }
        [JsonConverter(typeof(ZeroBasedIndexConverter))]
        public int EndLine { get; set; }
        [JsonConverter(typeof(ZeroBasedIndexConverter))]
        public int EndColumn { get; set; }
        public string Text { get; set; }
    }

    public class SymbolLocation : QuickFix
    {
        public string Kind { get; set; }
        public string ContainingSymbolName { get; set; }
        public SourceGeneratedFileInfo GeneratedFileInfo { get; set; }
    }

    public class QuickFixResponse : IAggregateResponse
    {
        public IEnumerable<QuickFix> QuickFixes { get; set; }
    }

o#/sourcegeneratedfile
    public record SourceGeneratedFileInfo
    {
        public Guid ProjectGuid { get; init; }
        public Guid DocumentGuid { get; init; }
    }

    public sealed record SourceGeneratedFileResponse
    {
        public string? SourceName { get; init; }
        public string? Source { get; init; }
    }
--]]

-- Options:
-- 1. Optimal approach - request using o#/v2/gotodefinition and handle response
-- 2. Sub-optimal approach - look if response contains $metadata$ or non-existant files, if yes - repeat using 1st option.

local M = {}

M.get_omnisharp_client = function()
  local clients = vim.lsp.buf_get_clients(0)
  for _, client in pairs(clients) do
    if client.name == "omnisharp" or client.name == "omnisharp_mono" then
      return client
    end
  end
end

M.buf_from_source = function(file_name, source, client_id)
  local normalized = string.gsub(source, '\r\n', '\n')
  local source_lines = utils.split(normalized, '\n')

  local bufnr = utils.get_or_create_buf(file_name)
  -- TODO: check if bufnr == 0 -> error
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)
  vim.api.nvim_buf_set_option(bufnr, 'readonly', false)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, source_lines)
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
  vim.api.nvim_buf_set_option(bufnr, 'readonly', true)
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'cs')
  vim.api.nvim_buf_set_option(bufnr, 'modified', false)

  vim.lsp.buf_attach_client(bufnr, client_id)

  return bufnr, file_name
end

-- Creates a buffer from metadata response.
M.buf_from_metadata = function(response, client_id)
  local normalized_file_name = vim.fs.normalize('/' .. response.SourceName)
  return M.buf_from_source(normalized_file_name, response.Source, client_id)
end

-- Creates a buffer from sourcegeneratedfile response.
M.buf_from_sourcegeneratedfile = function(response, client_id)
  local normalized_file_name = vim.fs.normalize('/' .. response.SourceName)
  return M.buf_from_source(normalized_file_name, response.Source, client_id)
end

-- Handles gotodefinition response and returns locations in nvim format
M.handle_gotodefinition = function(err, result, ctx, config)
  if err then
    vim.api.nvim_err_writeln('Error when executing ' .. 'o#/v2/gotodefinition' .. ' : ' .. err)
  end

  local lsp_client = vim.lsp.get_client_by_id(ctx.client_id)
  local locations = {}

  if not result.Definitions then
    return locations
  end

  for _, definition in ipairs(result.Definitions) do
    -- load metadata file if available
    if definition.MetadataSource then
      local params = {
        timeout = 5000,
      }

      -- matches what request expects
      for k,v in pairs(definition.MetadataSource) do params[k] = v end

      local result, err = lsp_client.request_sync('o#/metadata', params, 10000)
      if not err then
        local bufnr, name = M.buf_from_metadata(result.result, lsp_client.id)
      else
        vim.api.nvim_err_writeln('Error when executing ' .. 'o#/metadata' .. ' : ' .. err)
      end
    end

    -- load sourcegenerated file if available
    if definition.SourceGeneratedFileInfo then
      local params = {
        timeout = 5000,
      }

      -- matches what request expects
      for k,v in pairs(definition.SourceGeneratedFileInfo) do params[k] = v end

      local result, err = lsp_client.request_sync('o#/sourcegeneratedfile', params, 10000)
      if not err then
        local bufnr, name = M.buf_from_sourcegeneratedfile(result.result, lsp_client.id)
      else
        vim.api.nvim_err_writeln('Error when executing ' .. 'o#/sourcegeneratedfile' .. ' : ' .. err)
      end
    end

    local range = {}
    range['start'] = {
      line = definition.Location.Range.Start.Line,
      character = definition.Location.Range.Start.Column,
    }
    range['end'] = {
      line = definition.Location.Range.End.Line,
      character = definition.Location.Range.End.Column,
    }

    local fileName = definition.Location.FileName

    if fileName[1] ~= '/' then
      fileName = '/' .. fileName
    end

    local location = {
      uri = 'file://' .. vim.fs.normalize(fileName),
      range = range
    }

    table.insert(locations, location)
  end


  return locations
  -- invoke underlying handler
  if #locations > 1 then
    utils.set_qflist_locations(locations, lsp_client.offset_encoding)
    vim.api.nvim_command("copen")
    return true
  else
    vim.lsp.util.jump_to_location(locations[1], lsp_client.offset_encoding)
    return true
  end
end


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

-- Gets metadata for all locations with $metadata$
-- Returns map of fetched files.
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
        if not err and result.result.Source == nil then
          print("No definition found")
          return nil
        end
        if not err and result.result.Source ~= nil then
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

    local fileName = definition.Location.FileName

    if fileName[1] ~= '/' then
      fileName = '/' .. fileName
    end

    local location = {
      uri = 'file://' .. fileName,
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

-- Takes received locations and tries to load buffers for referenced metadata files.
-- If locations did not contain metadata files, false is returned, indicating that handler did not do anything.
M.handle_locations = function(locations, offset_encoding)
  local fetched = M.get_metadata(locations)

  if fetched == nil then
    return true end
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

M.handler_telescope = function(err, result, ctx, _, opts)
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
      M.handle_locations_telescope(locations, client.offset_encoding, opts)
    end
  end


  local testparams = {
    fileName = string.gsub(ctx.params.textDocument.uri, 'file://', '') ,
    column = ctx.params.position.character,
    line = ctx.params.position.line,
  }

  local _, __ = client.request_sync('o#/v2/gotodefinition', testparams, 10000)

  local locations = M.textdocument_definition_to_locations(result)
  M.handle_locations_telescope(locations, client.offset_encoding, opts)
end

M.telescope_lsp_definitions = function(opts)
  if not telescope_exists then
    error("Telescope is not available, this function only works with Telescope.")
  end

  local client = M.get_omnisharp_client()
  if client then
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)

    local handler = function(err, result, ctx, config)
      ctx.params = params
      M.handler_telescope(err, result, ctx, config, opts)
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

M.lsp_definitions_v2 = function()
  local client = M.get_omnisharp_client()
  if client then
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)

    local handler = function(err, result, ctx, config)
      ctx.params = params
      M.handle_gotodefinition(err, result, ctx, config)
    end

    local gotodefinitionParams = {
      fileName = string.gsub(params.textDocument.uri, 'file://', ''),
      column = params.position.character,
      line = params.position.line,
    }

    client.request('o#/v2/gotodefinition', gotodefinitionParams, handler)
  end
end


M.lsp_references = function()
  local client = M.get_omnisharp_client()
  if client then
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    local gotodefinitionParams = {
      fileName = M.file_name_for_gotodefinition(params.textDocument.uri),
      column = params.position.character,
      line = params.position.line,
    }

    client.request('o#/findusages', gotodefinitionParams, function(err, result, ctx, config) end)
  end
end
return M
