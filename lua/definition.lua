local utils = require("omnisharp_extended/utils")
local o_utils = require("omnisharp_utils")

local pickers = nil
local finders = nil
local conf = nil
local telescope_exists, make_entry = pcall(require, "telescope.make_entry")
if telescope_exists then
  pickers = require("telescope.pickers")
  finders = require("telescope.finders")
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
--]]

local M = {}

-- Handles gotodefinition response and returns locations in nvim format
M.handle_gotodefinition = function(err, result, ctx, config)
  if err then
    vim.api.nvim_err_writeln("Error when executing " .. "o#/v2/gotodefinition" .. " : " .. err.message)
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
      for k, v in pairs(definition.MetadataSource) do
        params[k] = v
      end

      o_utils.load_metadata_doc(params, lsp_client)
    end

    -- load sourcegenerated file if available
    if definition.SourceGeneratedFileInfo then
      local params = {
        timeout = 5000,
      }

      -- matches what request expects
      for k, v in pairs(definition.SourceGeneratedFileInfo) do
        params[k] = v
      end

      o_utils.load_sourcegen_doc(params, lsp_client)
    end

    -- remap definition to nvim lsp location
    local range = {}
    range["start"] = {
      line = definition.Location.Range.Start.Line,
      character = definition.Location.Range.Start.Column,
    }
    range["end"] = {
      line = definition.Location.Range.End.Line,
      character = definition.Location.Range.End.Column,
    }

    local fileName = definition.Location.FileName

    if fileName[1] ~= "/" then
      fileName = "/" .. fileName
    end

    local location = {
      uri = "file://" .. vim.fs.normalize(fileName),
      range = range,
    }

    table.insert(locations, location)
  end

  return locations
end

M.textdocument_definition_flatten = function(result)
  if not vim.tbl_islist(result) then
    return { result }
  end

  return result
end

-- Retries definition command using custom logic if result contains "special" files
M.handler = function(err, result, ctx, config)
  local client = utils.get_omnisharp_client()
  if
    o_utils.has_meta_or_sourcegen(M.textdocument_definition_flatten(result))
    or string.find(ctx.params.textDocument.uri, "^file:///%$metadata%$/.*$")
  then
    M.lsp_definitions()
  else
    return vim.lsp.handlers["textDocument/definition"](err, result, ctx, config)
  end
end

M.telescope_lsp_definitions_handler = function(err, result, ctx, config, opts)
  opts = opts or {}
  local lsp_client = vim.lsp.get_client_by_id(ctx.client_id)
  local locations = M.handle_gotodefinition(err, result, ctx, config)

  if #locations == 0 then
    vim.notify("No definition found")
  elseif #locations == 1 and opts.jump_type ~= "never" then
    if opts.jump_type == "tab" then
      vim.cmd("tabedit")
    elseif opts.jump_type == "split" then
      vim.cmd("new")
    elseif opts.jump_type == "vsplit" then
      vim.cmd("vnew")
    end
    vim.lsp.util.jump_to_location(locations[1], lsp_client.offset_encoding)
  else
    locations = vim.lsp.util.locations_to_items(locations, lsp_client.offset_encoding)
    pickers
      .new(opts, {
        prompt_title = "LSP Definitions",
        finder = finders.new_table({
          results = locations,
          entry_maker = opts.entry_maker or make_entry.gen_from_quickfix(opts),
        }),
        previewer = conf.qflist_previewer(opts),
        sorter = conf.generic_sorter(opts),
      })
      :find()
  end
end

M.telescope_lsp_definitions = function(opts)
  if not telescope_exists then
    error("Telescope is not available, this function only works with Telescope.")
  end

  local client = utils.get_omnisharp_client()
  if client then
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    local gotodefinitionParams = {
      fileName = o_utils.file_name_for_omnisharp(params.textDocument.uri),
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

    client.request("o#/v2/gotodefinition", gotodefinitionParams, handler)
  end
end

M.lsp_definitions_handler = function(err, result, ctx, config)
  local lsp_client = vim.lsp.get_client_by_id(ctx.client_id)
  local locations = M.handle_gotodefinition(err, result, ctx, config)

  if #locations > 1 then
    utils.set_qflist_locations(locations, lsp_client.offset_encoding)
    vim.api.nvim_command("copen")
  elseif #locations == 1 then
    vim.lsp.util.jump_to_location(locations[1], lsp_client.offset_encoding)
  else
    vim.notify("No definition found")
  end
end

M.lsp_definitions = function()
  local client = utils.get_omnisharp_client()
  if client then
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    local gotodefinitionParams = {
      fileName = o_utils.file_name_for_omnisharp(params.textDocument.uri),
      column = params.position.character,
      line = params.position.line,
    }

    client.request("o#/v2/gotodefinition", gotodefinitionParams, M.lsp_definitions_handler)
  end
end

return M
