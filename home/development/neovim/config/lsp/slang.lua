---@type vim.lsp.Config
return {
  cmd = { "slangd" },
  filetypes = { "shaderslang", "hlsl" },
  root_markers = { ".git" },
}
