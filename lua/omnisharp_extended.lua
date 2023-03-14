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

    -- remap definition to nvim lsp location
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
end

M.file_name_for_gotodefinition = function(file_name)
  local file_name = string.gsub(file_name, 'file://', '')
  if string.find(file_name, '^/%$metadata%$/.*$') then
    file_name = file_name:sub(2)
  end

  return file_name
end

M.textdocument_definition_flatten = function(result)
  if not vim.tbl_islist(result) then
    return { result }
  end

  return result
end

M.has_meta_or_sourcegen = function(result)
  local result = M.textdocument_definition_flatten(result)
  for _, definition in ipairs(result) do
    local file_name = string.gsub(definition.uri, 'file://', '')
    local is_metadata = string.find(file_name, '^/%$metadata%$/.*$')
    -- not sure how else to check for sourcegen file
    local exists = utils.file_exists(file_name)

    if is_metadata or not exists then
      return true
    end
  end
end

-- Retries definition command using custom logic if result contains "special" files
M.handler = function(err, result, ctx, config)
  local client = M.get_omnisharp_client()
  if M.has_meta_or_sourcegen(result) or string.find(ctx.params.textDocument.uri, '^file:///%$metadata%$/.*$') then
    M.lsp_definitions()
  else
    return vim.lsp.handlers['textDocument/definition'](err, result, ctx, config)
  end
end

M.telescope_lsp_definitions_handler = function(err, result, ctx, config, opts)
  opts = opts or {}
  local lsp_client = vim.lsp.get_client_by_id(ctx.client_id)
  local locations = M.handle_gotodefinition(err, result, ctx, config)

  -- not sure how to handle telescope options

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
    vim.lsp.util.jump_to_location(locations[1], lsp_client.offset_encoding)
  else
    locations = vim.lsp.util.locations_to_items(locations, lsp_client.offset_encoding)
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

M.telescope_lsp_definitions = function(opts)
  if not telescope_exists then
    error("Telescope is not available, this function only works with Telescope.")
  end

  local client = M.get_omnisharp_client()
  if client then
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    local gotodefinitionParams = {
      fileName = M.file_name_for_gotodefinition(params.textDocument.uri),
      column = params.position.character,
      line = params.position.line,
    }

    -- If invoked with telescope options, create closure that passes opts to real handler
    local handler = M.telescope_lsp_definitions_handler
    if opts then
      handler = function(err, result, ctx, config)
        M.telescope_lsp_definitions_handler(err, result, ctx, config, opts)
      end
    end

    client.request('o#/v2/gotodefinition', gotodefinitionParams, handler)
  end
end

M.lsp_definitions_handler = function(err, result, ctx, config)
  local lsp_client = vim.lsp.get_client_by_id(ctx.client_id)
  local locations = M.handle_gotodefinition(err, result, ctx, config)

  if #locations > 1 then
    utils.set_qflist_locations(locations, lsp_client.offset_encoding)
    vim.api.nvim_command("copen")
    return true
  else
    vim.lsp.util.jump_to_location(locations[1], lsp_client.offset_encoding)
    return true
  end
end

M.lsp_definitions = function()
  local client = M.get_omnisharp_client()
  if client then
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    local gotodefinitionParams = {
      fileName = M.file_name_for_gotodefinition(params.textDocument.uri),
      column = params.position.character,
      line = params.position.line,
    }

    client.request('o#/v2/gotodefinition', gotodefinitionParams, M.lsp_definitions_handler)
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
