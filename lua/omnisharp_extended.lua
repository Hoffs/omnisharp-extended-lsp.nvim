local m_definition = require("definition")
local m_type_definition = require("type_definition")
local m_references = require("references")
local m_implementation = require("implementation")
local o_utils = require("omnisharp_utils")

local M = {}

-- kept for back-compat, new naming follows original LSP naming
M.handler = m_definition.handler
M.lsp_definitions = m_definition.omnisharp_command
M.telescope_lsp_definitions = m_definition.telescope_command

M.lsp_definition = m_definition.omnisharp_command
M.telescope_lsp_definition = m_definition.telescope_command
M.definition_handler = m_definition.handler

M.lsp_type_definition = m_type_definition.omnisharp_command
M.telescope_lsp_type_definition = m_type_definition.telescope_command
M.type_definition_handler = m_type_definition.handler

M.lsp_references = m_references.omnisharp_command
M.telescope_lsp_references = m_references.telescope_command
M.references_handler = m_references.handler

M.lsp_implementation = m_implementation.omnisharp_command
M.telescope_lsp_implementation = m_implementation.telescope_command
M.implementation_handler = m_implementation.handler

return M
