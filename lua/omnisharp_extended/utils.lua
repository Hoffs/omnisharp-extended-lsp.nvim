local U = {}

U.abs_filename = function(filename)
  if vim.fn.has("win32") == 1 then
    -- either c:/something/something or //something/something
    if filename:sub(2, 2) == ":" or (filename:sub(1, 1) == filename:sub(2, 2) and filename:sub(1, 1) == "/") then
      return filename
    else
      return "//" .. filename
    end
  else
    if filename:sub(1, 1) == "~" or filename:sub(1, 1) == "/" then
      return filename
    else
      return "/" .. filename
    end
  end
end

U.hex_to_char = function(x)
  return string.char(tonumber(x, 16))
end

U.urldecode = function(url)
  if url == nil then
    return
  end
  url = url:gsub("+", " ")
  url = url:gsub("%%(%x%x)", U.hex_to_char)
  return url
end

U.split = function(str, delimiter)
  -- https://gist.github.com/jaredallard/ddb152179831dd23b230
  local result = {}
  local from = 1
  local delim_from, delim_to = string.find(str, delimiter, from)
  while delim_from do
    table.insert(result, string.sub(str, from, delim_from - 1))
    from = delim_to + 1
    delim_from, delim_to = string.find(str, delimiter, from)
  end
  table.insert(result, string.sub(str, from))
  return result
end

U.set_qflist_locations = function(locations, offset_encoding)
  local items = vim.lsp.util.locations_to_items(locations, offset_encoding)
  vim.fn.setqflist({}, " ", {
    title = "Language Server",
    items = items,
  })
end

U.file_exists = function(name)
  local f = io.open(name, "r")
  if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
end

U.get_omnisharp_client = function()
  local clients = nil;
  if vim.lsp.get_clients ~= nil then
    clients = vim.lsp.get_clients({ buffer = 0 })
  else
    clients = vim.lsp.buf_get_clients(0)
  end

  for _, client in pairs(clients) do
    if client.name == "omnisharp" or client.name == "omnisharp_mono" then
      return client
    end
  end
end

U.buf_from_source = function(file_name, source, client_id)
  local normalized_source = string.gsub(source, "\r\n", "\n")
  local source_lines = U.split(normalized_source, "\n")

  local bufnr = vim.uri_to_bufnr("file://" .. file_name)
  -- TODO: check if bufnr == 0 -> error
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
  vim.api.nvim_set_option_value("readonly", false, { buf = bufnr })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, source_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
  vim.api.nvim_set_option_value("readonly", true, { buf = bufnr })
  vim.api.nvim_set_option_value("filetype", "cs", { buf = bufnr })
  vim.api.nvim_set_option_value("modified", false, { buf = bufnr })
  vim.api.nvim_buf_set_var(bufnr, "omnisharp_extended_file_name", file_name)

  vim.lsp.buf_attach_client(bufnr, client_id)

  return bufnr, vim.api.nvim_buf_get_name(bufnr)
end

U.bufname_from_bufnr = function(bufnr)
  local maybe_name = U.buf_path_map[bufnr]
  if maybe_name == nil then
    maybe_name = vim.api.nvim_buf_get_name(bufnr)
  end

  return maybe_name
end

return U
