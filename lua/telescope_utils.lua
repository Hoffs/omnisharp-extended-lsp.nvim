local pickers = nil
local finders = nil
local conf = nil
local telescope_exists, make_entry = pcall(require, "telescope.make_entry")
if telescope_exists then
  pickers = require("telescope.pickers")
  finders = require("telescope.finders")
  conf = require("telescope.config").values
end

local M = {}

M.list_or_jump = function(title, locations, lsp_client, opts)
  if #locations == 0 then
    vim.notify("No locations found")
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
        prompt_title = title,
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

return M
