local utils = require("omnisharp_extended/utils")
local o_utils = require("omnisharp_utils")
local loc_utils = require("location_utils")
local islist = vim.islist or vim.tbl_islist

function flatten_lsp_locations(result)
  if not islist(result) then
    return { result }
  end

  return result
end

local Command = {
  title = "LSP Definitions",
  lsp_cmd_name = "textDocument/definition",
  omnisharp_cmd_name = "o#/v2/gotodefinition",
  omnisharp_result_to_locations = function(err, result, ctx, config) end,
  location_callback = function(locations, lsp_client) end,
  telescope_location_callback = function(title, params, locations, lsp_client, opts) end,
}

function Command:new(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  return o
end

function Command:omnisharp_cmd_handler(err, result, ctx, config)
  local lsp_client = vim.lsp.get_client_by_id(ctx.client_id)
  local locations = self.omnisharp_result_to_locations(err, result, ctx, config)
  self.location_callback(locations, lsp_client)
end

function Command:omnisharp_cmd()
  local client = utils.get_omnisharp_client()
  if client then
    client.request(self.omnisharp_cmd_name, o_utils.cmd_params(client), function(err, result, ctx, config)
      self:omnisharp_cmd_handler(err, result, ctx, config)
    end)
  end
end

function Command:handler(err, result, ctx, config)
  if
    o_utils.has_meta_or_sourcegen(flatten_lsp_locations(result))
    or string.find(ctx.params.textDocument.uri, ".*%$metadata%$/.*$")
  then
    self:omnisharp_cmd()
  else
    return vim.lsp.handlers[self.lsp_cmd_name](err, result, ctx, config)
  end
end

function Command:telescope_cmd_handler(err, result, ctx, config, opts)
  local lsp_client = vim.lsp.get_client_by_id(ctx.client_id)
  local locations = self.omnisharp_result_to_locations(err, result, ctx, config)
  self.telescope_location_callback(self.title, ctx.params, locations, lsp_client, opts)
end

function Command:telescope_cmd(opts)
  local telescope_exists = pcall(require, "telescope.make_entry")
  if not telescope_exists then
    error("Telescope is not available, this function only works with Telescope.")
  end
  local client = utils.get_omnisharp_client()
  if client then
    -- closure with passed in telescope options
    local handler = function(err, result, ctx, config)
      self:telescope_cmd_handler(err, result, ctx, config, opts)
    end
    client.request(self.omnisharp_cmd_name, o_utils.cmd_params(client, opts), handler)
  end
end

return Command
