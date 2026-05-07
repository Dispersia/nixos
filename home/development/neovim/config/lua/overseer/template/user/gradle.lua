return {
  generator = function(_, cb)
    local gradlew = vim.fn.findfile("gradlew", ".;")
    if gradlew == "" then
      cb({})
      return
    end

    local project_dir = vim.fn.fnamemodify(gradlew, ":p:h")
    local gradlew_path = vim.fn.fnamemodify(gradlew, ":p")

    local handle = io.popen(gradlew_path .. " tasks --console=plain 2>/dev/null")
    if not handle then
      cb({})
      return
    end

    local templates = {}
    for line in handle:lines() do
      local task = line:match("^(%S+) %- ")
      if task then
        table.insert(templates, {
          name = "gradle " .. task,
          builder = function()
            return {
              cmd = { gradlew_path },
              args = { task },
              cwd = project_dir,
              components = { "default" },
            }
          end,
        })
      end
    end
    handle:close()

    cb(templates)
  end,
  condition = {
    filetype = { "kotlin", "java", "groovy" },
  },
}
