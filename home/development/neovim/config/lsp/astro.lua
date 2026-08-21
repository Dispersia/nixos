---@type vim.lsp.Config
local function first_glob(pattern)
	return vim.fn.glob(pattern, false, true)[1]
end

local function find_tsdk(root_dir)
	local project = root_dir and (root_dir .. "/node_modules/typescript/lib")
	if project and vim.uv.fs_stat(project .. "/typescript.js") then
		return project
	end

	local exe = vim.fn.exepath("astro-ls")
	if exe == "" then
		return nil
	end

	local real = vim.uv.fs_realpath(exe) or exe
	for dir in vim.fs.parents(real) do
		local hit = first_glob(dir .. "/node_modules/typescript/lib/typescript.js")
			or first_glob(dir .. "/node_modules/.pnpm/typescript@*/node_modules/typescript/lib/typescript.js")
		if hit then
			return vim.fs.dirname(hit)
		end
	end

	return nil
end

return {
	cmd = { "astro-ls", "--stdio" },
	filetypes = { "astro" },
	root_markers = { "tsconfig.json", "package.json", "jsconfig.json", ".git" },
	init_options = {
		typescript = {},
	},
	before_init = function(_, config)
		local tsdk = find_tsdk(config.root_dir)
		if not tsdk then
			vim.notify("astro-ls: could not locate a typescript tsdk", vim.log.levels.WARN)
			return
		end
		config.init_options.typescript.tsdk = tsdk
	end,
}
