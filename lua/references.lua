local utils = require("omnisharp_extended/utils")
local o_utils = require("omnisharp_utils")
local t_utils = require("telescope_utils")

local pickers = nil
local finders = nil
local conf = nil
local telescope_exists = pcall(require, "telescope.make_entry")

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

local M = {}

M.handle_findusages = function(err, result, ctx, config)
  if err then
    vim.api.nvim_err_writeln("Error when executing " .. "o#/findusages" .. " : " .. err.message)
  end

  local lsp_client = vim.lsp.get_client_by_id(ctx.client_id)

  if not result.QuickFixes then
    return {}
  end

  return o_utils.quickfixes_to_locations(result.QuickFixes, lsp_client)
end

M.telescope_lsp_references_handler = function(err, result, ctx, config)
  opts = opts or {}
  local lsp_client = vim.lsp.get_client_by_id(ctx.client_id)
  local locations = M.handle_findusages(err, result, ctx, config)

  t_utils.list_or_jump("LSP References", locations, lsp_client, opts)
end

M.telescope_lsp_references = function(opts)
  if not telescope_exists then
    error("Telescope is not available, this function only works with Telescope.")
  end

  local client = utils.get_omnisharp_client()
  if client then
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    local findusagesParams = {
      fileName = o_utils.file_name_for_omnisharp(params.textDocument.uri),
      column = params.position.character,
      line = params.position.line,
    }

    -- If invoked with telescope options, create closure that passes opts to real handler
    local handler = M.telescope_lsp_references_handler
    if opts then
      handler = function(err, result, ctx, config)
        M.telescope_lsp_references_handler(err, result, ctx, config, opts)
      end
    end

    client.request("o#/findusages", findusagesParams, handler)
  end
end

M.lsp_references_handler = function(err, result, ctx, config)
  local lsp_client = vim.lsp.get_client_by_id(ctx.client_id)
  local locations = M.handle_findusages(err, result, ctx, config)

  if #locations > 0 then
    utils.set_qflist_locations(locations, lsp_client.offset_encoding)
    vim.api.nvim_command("copen")
    return true
  else
    vim.notify("No references found")
  end
end

M.lsp_references = function()
  local client = utils.get_omnisharp_client()
  if client then
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    local findusagesParams = {
      fileName = o_utils.file_name_for_omnisharp(params.textDocument.uri),
      column = params.position.character,
      line = params.position.line,
    }

    client.request("o#/findusages", findusagesParams, M.lsp_references_handler)
  end
end

M.handler = function(err, result, ctx, config)
  local client = utils.get_omnisharp_client()
  if o_utils.has_meta_or_sourcegen(result) or string.find(ctx.params.textDocument.uri, "^file:///%$metadata%$/.*$") then
    M.lsp_references()
  else
    return vim.lsp.handlers["textDocument/references"](err, result, ctx, config)
  end
end

return M
