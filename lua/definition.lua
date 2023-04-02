local utils = require("omnisharp_extended/utils")
local o_utils = require("omnisharp_utils")
local loc_utils = require("location_utils")
local Command = require("generic_command")

local telescope_exists = pcall(require, "telescope.make_entry")

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

function gotodefinition_to_locations(err, result, ctx, config)
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

local gLspDefinitions = Command:new({
  title = "LSP Definitions",
  lsp_cmd_name = "textDocument/definition",
  omnisharp_cmd_name = "o#/v2/gotodefinition",
  omnisharp_result_to_locations = gotodefinition_to_locations,
  location_callback = loc_utils.qflist_list_or_jump,
  telescope_location_callback = loc_utils.telescope_list_or_jump,
})

return {
  handler = function(err, result, ctx, config)
    gLspDefinitions:handler(err, result, ctx, config)
  end,
  omnisharp_command = function()
    gLspDefinitions:omnisharp_cmd()
  end,
  telescope_command = function()
    gLspDefinitions:telescope_cmd()
  end,
}
