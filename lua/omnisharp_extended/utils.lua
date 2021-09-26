local U = {}

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
  local result = { }
  local from  = 1
  local delim_from, delim_to = string.find(str, delimiter, from)
  while delim_from do
    table.insert(result, string.sub(str, from , delim_from-1))
    from  = delim_to + 1
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

return U
