local function find_namespace(gradle_file)
  local handle = io.popen("grep 'namespace' " .. gradle_file .. " 2>/dev/null")
  if not handle then return nil end
  for line in handle:lines() do
    local ns = line:match('namespace%s*=%s*"([^"]+)"')
      or line:match("namespace%s+['\"]([^'\"]+)['\"]")
    if ns then
      handle:close()
      return ns
    end
  end
  handle:close()
  return nil
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
  return "app"
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
    local module = detect_module(project_dir)

    local namespace = find_namespace(project_dir .. "/" .. module .. "/build.gradle.kts")
      or find_namespace(project_dir .. "/" .. module .. "/build.gradle")

    local templates = {
      {
        name = "Android: Build",
        builder = function()
          return {
            cmd = { gradlew_path },
            args = { "build" },
            cwd = project_dir,
            components = { "default" },
          }
        end,
      },
    }

    if namespace then
      table.insert(templates, {
        name = "Android: Build & Install (" .. module .. ")",
        builder = function()
          return {
            cmd = { "sh" },
            args = {
              "-c",
              gradlew_path .. " :" .. module .. ":assembleDebug"
                .. " && DEVICE=$(adb devices | awk 'NR==2{print $1}')"
                .. ' && [ -n "$DEVICE" ]'
                .. " && adb -s $DEVICE install "
                .. project_dir .. "/" .. module .. "/build/outputs/apk/debug/" .. module .. "-debug.apk"
                .. " && adb -s $DEVICE shell monkey -p "
                .. namespace
                .. " 1",
            },
            cwd = project_dir,
            components = { "default" },
          }
        end,
      })
    end

    cb(templates)
  end,
  condition = {
    filetype = { "kotlin" },
  },
}
