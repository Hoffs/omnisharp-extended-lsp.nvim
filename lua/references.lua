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
    return
  end

  local lsp_client = vim.lsp.get_client_by_id(ctx.client_id)
  local locations = {}

  if not result.QuickFixes then
    return locations
  end

  for _, usage in ipairs(result.QuickFixes) do
    -- load sourcegenerated file if available
    if usage.GeneratedFileInfo then
      local params = {
        timeout = 5000,
      }

      -- matches what request expects
      for k, v in pairs(usage.GeneratedFileInfo) do
        params[k] = v
      end

      o_utils.load_sourcegen_doc(params, lsp_client)
    end

    -- remap definition to nvim lsp location
    local range = {}
    range["start"] = {
      line = usage.Line,
      character = usage.Column,
    }
    range["end"] = {
      line = usage.EndLine,
      character = usage.EndColumn,
    }

    local fileName = usage.FileName

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

M.telescope_lsp_references_handler = function(err, result, ctx, config)
  opts = opts or {}
  local lsp_client = vim.lsp.get_client_by_id(ctx.client_id)
  local locations = M.handle_findusages(err, result, ctx, config)

  if #locations == 0 then
    vim.notify("No references found")
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
        prompt_title = "LSP References",
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
