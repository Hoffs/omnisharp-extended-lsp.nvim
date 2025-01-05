local utils = require("omnisharp_extended/utils")

local OU = {}

--[[
OmniSharp Protocol:

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

-- params = {
--   AssemblyName
--   TypeName
--   ProjectName
--   VersionNumber
--   Language
-- }
OU.load_metadata_doc = function(params, lsp_client)
  local result, err = lsp_client.request_sync("o#/metadata", params, 10000)
  if not err then
    local response = result.result

    -- In some cases metadata might return nothing,
    -- see https://github.com/Hoffs/omnisharp-extended-lsp.nvim/issues/11
    -- In that case return nil and handle this as non-existant location
    if vim.tbl_isempty(response) then
      return nil
    end

    local bufnr, name = utils.buf_from_source(response.SourceName, response.Source, lsp_client.id)
    return bufnr, name
  else
    vim.api.nvim_err_writeln("Error when executing " .. "o#/metadata" .. " : " .. err)
  end
end

-- params = {
--   ProjectGuid
--   DocumentGuid
-- }
OU.load_sourcegen_doc = function(params, lsp_client)
  params.timeout = 5000
  local result, err = lsp_client.request_sync("o#/sourcegeneratedfile", params, 10000)
  if not err then
    -- Creates a buffer from sourcegeneratedfile response.
    local response = result.result
    local bufnr, name = utils.buf_from_source(response.SourceName, response.Source, lsp_client.id)
    return bufnr, name
  else
    vim.api.nvim_err_writeln("Error when executing " .. "o#/sourcegeneratedfile" .. " : " .. err)
  end
end

OU.has_meta_or_sourcegen = function(result)
  for _, definition in ipairs(result) do
    local file_name = OU.file_name_for_omnisharp(definition.uri)
    local is_metadata = string.find(file_name, "^%$metadata%$/.*$")
    -- not sure how else to check for sourcegen file, so just check for existence
    local exists = utils.file_exists(file_name)
    if is_metadata or not exists then
      return true
    end
  end

  return false
end

OU.file_name_for_omnisharp = function(file_name)
  local success, buf_file_name = pcall(vim.api.nvim_buf_get_var, 0, "omnisharp_extended_file_name")
  if success then
    return buf_file_name
  end

  return vim.uri_to_fname(file_name)
end

OU.quickfixes_to_locations = function(quickfixes, lsp_client)
  local locations = {}

  for _, qf in ipairs(quickfixes) do
    local buf_file_name = qf.FileName

    -- load sourcegenerated file if available
    if qf.GeneratedFileInfo then
      local params = {
        timeout = 5000,
      }

      -- matches what request expects
      for k, v in pairs(qf.GeneratedFileInfo) do
        params[k] = v
      end

      _, buf_file_name = OU.load_sourcegen_doc(params, lsp_client)
    end

    -- remap definition to nvim lsp location
    local range = {}
    range["start"] = {
      line = qf.Line,
      character = qf.Column,
    }
    range["end"] = {
      line = qf.EndLine,
      character = qf.EndColumn,
    }

    local location = {
      uri = "file://" .. buf_file_name,
      range = range,
    }

    table.insert(locations, location)
  end

  return locations
end

OU.cmd_params = function(lsp_client, opts)
  local params = vim.lsp.util.make_position_params(0, lsp_client.offset_encoding)
  local excludeDefinition = (opts and opts.excludeDefinition) or false
  return {
    fileName = OU.file_name_for_omnisharp(params.textDocument.uri),
    column = params.position.character,
    line = params.position.line,
    excludeDefinition = excludeDefinition
  }
end

return OU
