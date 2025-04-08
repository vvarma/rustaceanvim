---@mod rustaceanvim.config.server LSP configuration utility

local server = {}

---@class rustaceanvim.LoadRASettingsOpts
---
---(deprecated) File name or pattern to search for. Defaults to 'rust-analyzer.json'
---@field settings_file_pattern string|nil
---Default settings to merge the loaded settings into.
---@field default_settings table|nil

--- Load rust-analyzer settings from a JSON file,
--- falling back to the default settings if none is found or if it cannot be decoded.
---@param project_root string|nil The project root
---@param opts rustaceanvim.LoadRASettingsOpts|nil
---@return table server_settings
---@see https://rust-analyzer.github.io/book/configuration
function server.load_rust_analyzer_settings(project_root, opts)
  local config = require('rustaceanvim.config.internal')
  local os = require('rustaceanvim.os')

  local default_opts = { settings_file_pattern = 'rust-analyzer.json' }
  opts = vim.tbl_deep_extend('force', {}, default_opts, opts or {})
  local default_settings = opts.default_settings or config.server.default_settings
  local use_clippy = config.tools.enable_clippy and vim.fn.executable('cargo-clippy') == 1
  ---@diagnostic disable-next-line: undefined-field
  if
    default_settings['rust-analyzer'].check == nil
    and use_clippy
    and type(default_settings['rust-analyzer'].checkOnSave) ~= 'table'
  then
    ---@diagnostic disable-next-line: inject-field
    default_settings['rust-analyzer'].check = {
      command = 'clippy',
      extraArgs = { '--no-deps' },
    }
    if type(default_settings['rust-analyzer'].checkOnSave) ~= 'boolean' then
      ---@diagnostic disable-next-line: inject-field
      default_settings['rust-analyzer'].checkOnSave = true
    end
  end
  if not project_root then
    return default_settings
  end
  local results = vim.fn.glob(vim.fs.joinpath(project_root, opts.settings_file_pattern), true, true)
  if #results == 0 then
    return default_settings
  end
  vim.deprecate('rust-analyzer.json', "'.vscode/settings.json' or ':h exrc'", '6.0.0', 'rustaceanvim')
  local config_json = results[1]
  local content = os.read_file(config_json)
  if not content then
    vim.notify('Could not read ' .. config_json, vim.log.levels.WARN)
    return default_settings
  end
  local json = require('rustaceanvim.config.json')
  local rust_analyzer_settings = json.silent_decode(content)
  local ra_key = 'rust-analyzer'
  local has_ra_key = false
  for key, _ in pairs(rust_analyzer_settings) do
    if key:find(ra_key) ~= nil then
      has_ra_key = true
      break
    end
  end
  if has_ra_key then
    -- Settings json with "rust-analyzer" key
    json.override_with_rust_analyzer_json_keys(default_settings, rust_analyzer_settings)
  else
    -- "rust-analyzer" settings are top level
    json.override_with_json_keys(default_settings, rust_analyzer_settings)
  end
  return default_settings
end

---@return lsp.ClientCapabilities
function server.create_client_capabilities()
  local capabilities = vim.lsp.protocol.make_client_capabilities()

  -- send actions with hover request
  capabilities.experimental = {
    hoverActions = true,
    colorDiagnosticOutput = true,
    hoverRange = true,
    serverStatusNotification = true,
    snippetTextEdit = true,
    codeActionGroup = true,
    ssr = true,
  }

  -- enable auto-import
  capabilities.textDocument.completion.completionItem.resolveSupport = {
    properties = { 'documentation', 'detail', 'additionalTextEdits' },
  }

  -- rust analyzer goodies
  local experimental_commands = {
    'rust-analyzer.runSingle',
    'rust-analyzer.showReferences',
    'rust-analyzer.gotoLocation',
    'editor.action.triggerParameterHints',
  }
  if package.loaded['dap'] ~= nil then
    table.insert(experimental_commands, 'rust-analyzer.debugSingle')
  end

  ---@diagnostic disable-next-line: inject-field
  capabilities.experimental.commands = {
    commands = experimental_commands,
  }

  return capabilities
end

return server
