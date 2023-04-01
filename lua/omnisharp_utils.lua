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
    local bufnr, name = OU.buf_from_metadata(result.result, lsp_client.id)
  else
    vim.api.nvim_err_writeln("Error when executing " .. "o#/metadata" .. " : " .. err)
  end
end

-- Creates a buffer from metadata response.
OU.buf_from_metadata = function(response, client_id)
  local normalized_file_name = vim.fs.normalize("/" .. response.SourceName)
  return utils.buf_from_source(normalized_file_name, response.Source, client_id)
end

-- params = {
--   ProjectGuid
--   DocumentGuid
-- }
OU.load_sourcegen_doc = function(params, lsp_client)
  params.timeout = 5000
  local result, err = lsp_client.request_sync("o#/sourcegeneratedfile", params, 10000)
  if not err then
    local bufnr, name = OU.buf_from_sourcegeneratedfile(result.result, lsp_client.id)
  else
    vim.api.nvim_err_writeln("Error when executing " .. "o#/sourcegeneratedfile" .. " : " .. err)
  end
end

-- Creates a buffer from sourcegeneratedfile response.
OU.buf_from_sourcegeneratedfile = function(response, client_id)
  local normalized_file_name = vim.fs.normalize("/" .. response.SourceName)
  return utils.buf_from_source(normalized_file_name, response.Source, client_id)
end

OU.has_meta_or_sourcegen = function(result)
  for _, definition in ipairs(result) do
    local file_name = string.gsub(definition.uri, "file://", "")
    local is_metadata = string.find(file_name, "^/%$metadata%$/.*$")
    -- not sure how else to check for sourcegen file
    local exists = utils.file_exists(file_name)

    if is_metadata or not exists then
      return true
    end
  end
end

OU.file_name_for_omnisharp = function(file_name)
  local file_name = string.gsub(file_name, "file://", "")
  if string.find(file_name, "^/%$metadata%$/.*$") then
    file_name = file_name:sub(2)
  end

  return file_name
end

return OU