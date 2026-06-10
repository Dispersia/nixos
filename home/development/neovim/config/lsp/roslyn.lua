local util = require("util")

local function find_targets(root)
  local sln, slnx
  for name, type in vim.fs.dir(root, { depth = 4 }) do
    if type == "file" then
      if name:match("%.sln$") then
        sln = root .. "/" .. name
      elseif name:match("%.slnx$") then
        slnx = root .. "/" .. name
      end
    end
  end

  local solution = sln or slnx
  if solution then
    return { kind = "solution", uri = vim.uri_from_fname(solution) }
  end

  local csprojs = {}
  for name, type in vim.fs.dir(root, { depth = 6 }) do
    if type == "file" and name:match("%.csproj$") then
      table.insert(csprojs, vim.uri_from_fname(root .. "/" .. name))
    end
  end
  if #csprojs > 0 then
    return { kind = "projects", uris = csprojs }
  end
end

---@type vim.lsp.Config
return {
  cmd = {
    "Microsoft.CodeAnalysis.LanguageServer",
    "--logLevel=Information",
    "--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.log.get_filename()), "--stdio"
  },
  filetypes = { "cs" },
  cmd_env = {
    Configuration = vim.env.Configuration or "Debug",
  },
  capabilities = {
    textDocument = {
      diagnostic = {
        dynamicRegistration = true,
      },
    },
  },
  root_dir = function(bufnr, on_dir)
    local fname = vim.api.nvim_buf_get_name(bufnr)
    on_dir(util.root_pattern("*.slnx", "*.sln", "*.csproj", ".git")(fname))
  end,
  on_init = function(client)
    local root = client.root_dir
    if not root then
      return
    end
    local targets = find_targets(root)
    if not targets then
      return
    end
    if targets.kind == "solution" then
      client:notify("solution/open", { solution = targets.uri })
    else
      client:notify("project/open", { projects = targets.uris })
    end
  end,
}
