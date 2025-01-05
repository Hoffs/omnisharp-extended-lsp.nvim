local utils = require("omnisharp_extended/utils")

local M = {}

M.telescope_list_or_jump = function(title, params, locations, lsp_client, opts)
  local telescope_exists, make_entry = pcall(require, "telescope.make_entry")
  if not telescope_exists then
    print("Telescope is required for this action.")
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  opts = opts or {}

  if #locations == 0 then
    vim.notify("No locations found")
  elseif #locations == 1 and opts.jump_type ~= "never" then
    local current_uri = params.fileName
    local target_uri = locations[1].uri or locations[1].targetUri
    if current_uri ~= string.gsub(target_uri, "file://", "") then
      if opts.jump_type == "tab" then
        vim.cmd("tabedit")
      elseif opts.jump_type == "split" then
        vim.cmd("new")
      elseif opts.jump_type == "vsplit" then
        vim.cmd("vnew")
      end
    end

    if vim.lsp.util.show_document ~= nil then
      vim.lsp.util.show_document(locations[1], lsp_client.offset_encoding, { reuse_win = opts.reuse_win })
    else
      vim.lsp.util.jump_to_location(locations[1], lsp_client.offset_encoding, opts.reuse_win)
    end
  else
    locations = vim.lsp.util.locations_to_items(locations, lsp_client.offset_encoding)
    pickers
      .new(opts, {
        prompt_title = title,
        finder = finders.new_table({
          results = locations,
          entry_maker = opts.entry_maker or make_entry.gen_from_quickfix(opts),
        }),
        previewer = conf.qflist_previewer(opts),
        sorter = conf.generic_sorter(opts),
        push_cursor_on_edit = true,
        push_tagstack_on_edit = true,
      })
      :find()
  end
end

M.qflist_list = function(locations, lsp_client)
  if #locations > 0 then
    utils.set_qflist_locations(locations, lsp_client.offset_encoding)
    vim.api.nvim_command("copen")
    return true
  else
    vim.notify("No locations found")
  end
end

M.qflist_list_or_jump = function(locations, lsp_client)
  if #locations > 1 then
    utils.set_qflist_locations(locations, lsp_client.offset_encoding)
    vim.api.nvim_command("copen")
  elseif #locations == 1 then
    local show_document = vim.lsp.util.show_document or vim.lsp.util.jump_to_location
    show_document(locations[1], lsp_client.offset_encoding)
  else
    vim.notify("No locations found")
  end
end

return M
