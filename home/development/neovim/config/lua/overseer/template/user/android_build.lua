return {
  generator = function(_, cb)
    local gradlew = vim.fn.findfile("gradlew", ".;")
    if gradlew == "" then
      cb({})
      return
    end

    local project_dir = vim.fn.fnamemodify(gradlew, ":p:h")
    local gradlew_path = vim.fn.fnamemodify(gradlew, ":p")

    local namespace = nil
    local handle = io.popen("grep -r 'namespace' " .. project_dir .. "/app/build.gradle.kts 2>/dev/null")
    if handle then
      for line in handle:lines() do
        local ns = line:match('namespace%s*=%s*"([^"]+)"')
        if ns then
          namespace = ns
          break
        end
      end
      handle:close()
    end

    if not namespace then
      handle = io.popen("grep -r 'namespace' " .. project_dir .. "/app/build.gradle 2>/dev/null")
      if handle then
        for line in handle:lines() do
          local ns = line:match("namespace%s+['\"]([^'\"]+)['\"]")
            or line:match('namespace%s*=%s*"([^"]+)"')
          if ns then
            namespace = ns
            break
          end
        end
        handle:close()
      end
    end

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
        name = "Android: Build & Install",
        builder = function()
          return {
            cmd = { "sh" },
            args = {
              "-c",
              gradlew_path .. " build"
                .. " && DEVICE=$(adb devices | awk 'NR==2{print $1}')"
                .. ' && [ -n "$DEVICE" ]'
                .. " && adb -s $DEVICE install "
                .. project_dir
                .. "/app/build/outputs/apk/debug/app-debug.apk"
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
