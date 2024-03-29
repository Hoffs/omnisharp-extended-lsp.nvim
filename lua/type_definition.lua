local o_utils = require("omnisharp_utils")
local loc_utils = require("location_utils")
local Command = require("generic_command")

--[[
OmniSharp Protocol:

o#/v2/gototypedefinition
    public class GotoTypeDefinitionRequest : Request
    {
        public int Timeout { get; set; } = 10000;
        public bool WantMetadata { get; set; }
    }

    public record GotoTypeDefinitionResponse
    {
        public List<TypeDefinition>? Definitions { get; init; }
    }

    public record TypeDefinition
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

function gototypedefinition_to_locations(err, result, ctx, config)
  if err then
    vim.api.nvim_err_writeln("Error when executing " .. "o#/gototypedefinition" .. " : " .. err.message)
  end

  local lsp_client = vim.lsp.get_client_by_id(ctx.client_id)
  local locations = {}

  if not result or not result.Definitions then
    return locations
  end

  for _, typedefinition in ipairs(result.Definitions) do
    -- load metadata file if available

    local buf_file_name = typedefinition.Location.FileName
    if typedefinition.MetadataSource then
      local params = {
        timeout = 5000,
      }

      -- matches what request expects
      for k, v in pairs(typedefinition.MetadataSource) do
        params[k] = v
      end

      _, buf_file_name = o_utils.load_metadata_doc(params, lsp_client)
    end

    -- load sourcegenerated file if available
    if typedefinition.SourceGeneratedFileInfo then
      local params = {
        timeout = 5000,
      }

      -- matches what request expects
      for k, v in pairs(typedefinition.SourceGeneratedFileInfo) do
        params[k] = v
      end

      _, buf_file_name = o_utils.load_sourcegen_doc(params, lsp_client)
    end

    -- remap typedefinition to nvim lsp location
    local range = {}
    range["start"] = {
      line = typedefinition.Location.Range.Start.Line,
      character = typedefinition.Location.Range.Start.Column,
    }
    range["end"] = {
      line = typedefinition.Location.Range.End.Line,
      character = typedefinition.Location.Range.End.Column,
    }

    if buf_file_name ~= nil then
      local location = {
        uri = "file://" .. buf_file_name,
        range = range,
      }
      table.insert(locations, location)
    end
  end

  return locations
end

local gLsp = Command:new({
  title = "LSP TypeDefinitions",
  lsp_cmd_name = "textDocument/typeDefinition",
  omnisharp_cmd_name = "o#/gototypedefinition",
  omnisharp_result_to_locations = gototypedefinition_to_locations,
  location_callback = loc_utils.qflist_list_or_jump,
  telescope_location_callback = loc_utils.telescope_list_or_jump,
})

return {
  handler = function(err, result, ctx, config)
    gLsp:handler(err, result, ctx, config)
  end,
  omnisharp_command = function()
    gLsp:omnisharp_cmd()
  end,
  telescope_command = function(opts)
    gLsp:telescope_cmd(opts)
  end,
}
