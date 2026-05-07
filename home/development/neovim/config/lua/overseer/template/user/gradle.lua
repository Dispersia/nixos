local function find_app_id(gradle_file)
  local handle = io.popen("grep -E 'namespace|applicationId' " .. gradle_file .. " 2>/dev/null")
  if not handle then return nil end
  local app_id = nil
  for line in handle:lines() do
    local id = line:match('applicationId%s*=%s*"([^"]+)"')
      or line:match("applicationId%s+['\"]([^'\"]+)['\"]")
    if id then
      app_id = id
      break
    end
    if not app_id then
      id = line:match('namespace%s*=%s*"([^"]+)"')
        or line:match("namespace%s+['\"]([^'\"]+)['\"]")
      if id then app_id = id end
    end
  end
  handle:close()
  return app_id
end

local function detect_module(project_dir)
  local file_path = vim.fn.expand("%:p")
  local rel = file_path:sub(#project_dir + 2)
  local module = rel:match("^([^/]+)/")
  if module and vim.fn.filereadable(project_dir .. "/" .. module .. "/build.gradle.kts") == 1 then
    return module
  end
  if module and vim.fn.filereadable(project_dir .. "/" .. module .. "/build.gradle") == 1 then
    return module
  end
  return nil
end

local function has_direnv(project_dir)
  return vim.fn.filereadable(project_dir .. "/.envrc") == 1
end

local function wrap_cmd(project_dir, cmd)
  local wrapped = "cd " .. project_dir .. " && "
  if has_direnv(project_dir) then
    wrapped = wrapped .. "direnv exec . "
  end
  return wrapped .. cmd
end

return {
  generator = function(_, cb)
    local gradlew = vim.fn.findfile("gradlew", ".;")
    if gradlew == "" then
      cb({})
      return
    end

    local project_dir = vim.fn.fnamemodify(gradlew, ":p:h")
    local gradlew_path = vim.fn.fnamemodify(gradlew, ":p")

    local handle = io.popen(wrap_cmd(project_dir, gradlew_path .. " tasks --console=plain") .. " 2>/dev/null")
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
              cmd = { "sh" },
              args = { "-c", wrap_cmd(project_dir, gradlew_path .. " " .. task) },
              cwd = project_dir,
              components = { "default" },
            }
          end,
        })
      end
    end
    handle:close()

    local module = detect_module(project_dir)
    if module then
      local app_id = find_app_id(project_dir .. "/" .. module .. "/build.gradle.kts")
        or find_app_id(project_dir .. "/" .. module .. "/build.gradle")
      if app_id then
        table.insert(templates, 1, {
          name = "gradle installDebug & run (" .. module .. ")",
          builder = function()
            return {
              cmd = { "sh" },
              args = {
                "-c",
                wrap_cmd(project_dir, gradlew_path .. " :" .. module .. ":installDebug")
                  .. " && adb shell monkey -p " .. app_id .. " 1",
              },
              cwd = project_dir,
              components = { "default" },
            }
          end,
        })
      end
    end

    cb(templates)
  end,
  condition = {
    filetype = { "kotlin", "java", "groovy" },
  },
}
