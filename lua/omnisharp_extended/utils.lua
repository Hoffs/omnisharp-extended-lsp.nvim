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

U.get_or_create_buf = function(name)
  local buffers = vim.api.nvim_list_bufs()
  for _, buf in pairs(buffers) do
    local bufname = vim.api.nvim_buf_get_name(buf)

    if bufname == name then
      return buf
    end
  end

  local bufnr = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(bufnr, name)
  return bufnr
end

U.set_qflist_locations = function(locations, offset_encoding)
  local items = vim.lsp.util.locations_to_items(locations, offset_encoding)
  vim.fn.setqflist({}, " ", {
    title = "Language Server",
    items = items,
  })
end

U.jump_to_location = function(location, bufnr)
  if not bufnr then
    -- if bufnr is provided, assume its configured
    bufnr = vim.uri_to_bufnr(location.uri)
    vim.api.nvim_buf_set_option(0, "buflisted", true)
  end

  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_win_set_cursor(0, { location.range.start.line + 1, location.range.start.character })
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
  local clients = vim.lsp.buf_get_clients(0)
  for _, client in pairs(clients) do
    if client.name == "omnisharp" or client.name == "omnisharp_mono" then
      return client
    end
  end
end

U.buf_from_source = function(file_name, source, client_id)
  local normalized = string.gsub(source, "\r\n", "\n")
  local source_lines = U.split(normalized, "\n")

  local bufnr = U.get_or_create_buf(file_name)
  -- TODO: check if bufnr == 0 -> error
  vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
  vim.api.nvim_buf_set_option(bufnr, "readonly", false)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, source_lines)
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
  vim.api.nvim_buf_set_option(bufnr, "readonly", true)
  vim.api.nvim_buf_set_option(bufnr, "filetype", "cs")
  vim.api.nvim_buf_set_option(bufnr, "modified", false)

  vim.lsp.buf_attach_client(bufnr, client_id)

  return bufnr, vim.api.nvim_buf_get_name(bufnr)
end

return U
