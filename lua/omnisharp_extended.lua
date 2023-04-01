local m_definition = require("definition")
local m_references = require("references")
local m_implementation = require("implementation")

local M = {}

M.lsp_definitions = m_definition.lsp_definitions
M.telescope_lsp_definitions = m_definition.telescope_lsp_definitions
M.handler = m_definition.handler

M.lsp_references = m_references.lsp_references
M.telescope_lsp_references = m_references.telescope_lsp_references
M.references_handler = m_references.handler

M.lsp_implementation = m_implementation.lsp_implementation
M.implementation_handler = m_implementation.handler

return M
