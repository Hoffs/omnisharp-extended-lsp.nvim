local o_utils = require("omnisharp_utils")
local loc_utils = require("location_utils")
local Command = require("generic_command")

--[[
OmniSharp Protocol:

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
--]]

function usages_to_locations(err, result, ctx, config)
  if err then
    vim.api.nvim_err_writeln("Error when executing " .. "o#/findusages" .. " : " .. err.message)
  end

  local lsp_client = vim.lsp.get_client_by_id(ctx.client_id)

  if not result or not result.QuickFixes then
    return {}
  end

  return o_utils.quickfixes_to_locations(result.QuickFixes, lsp_client)
end

local gLsp = Command:new({
  title = "LSP References",
  lsp_cmd_name = "textDocument/references",
  omnisharp_cmd_name = "o#/findusages",
  omnisharp_result_to_locations = usages_to_locations,
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
