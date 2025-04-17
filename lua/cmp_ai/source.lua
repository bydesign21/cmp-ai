local cmp = require('cmp')
local api = vim.api
local conf = require('cmp_ai.config')
local utils = require('cmp_ai.utils')

local Source = {}

-- Store completion context and timer
local completion_state = {
  timer = nil,
  self = nil,
  ctx = nil,
  callback = nil
}

function Source:new(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  
  -- Create autocommands for cleanup and mode handling
  local group = api.nvim_create_augroup("CmpAICompletion", { clear = true })
  
  -- Stop completion when leaving insert mode
  api.nvim_create_autocmd("InsertLeave", {
    group = group,
    callback = function()
      if completion_state.timer then
        completion_state.timer:stop()
        completion_state.timer:close()
        completion_state.timer = nil
      end
      completion_state.self = nil
      completion_state.ctx = nil
      completion_state.callback = nil
    end,
  })
  
  return o
end

function Source:get_debug_name()
  return 'AI'
end

function Source:_do_complete(ctx, cb)
  -- Only proceed if we're still in insert mode
  if vim.fn.mode() ~= 'i' then
    return
  end

  if conf:get('notify') then
    conf:get('notify_callback')('Completion started')
  end
  
  local max_lines = conf:get('max_lines')
  local cursor = ctx.context.cursor
  local cur_line = ctx.context.cursor_line
  
  local cur_line_before = vim.fn.strpart(cur_line, 0, math.max(cursor.col - 1, 0), true)
  local cur_line_after = vim.fn.strpart(cur_line, math.max(cursor.col - 1, 0), vim.fn.strdisplaywidth(cur_line), true)

  local lines_before = api.nvim_buf_get_lines(0, math.max(0, cursor.line - max_lines), cursor.line, false)
  table.insert(lines_before, cur_line_before)
  local before = table.concat(lines_before, '\n')

  local lines_after = api.nvim_buf_get_lines(0, cursor.line + 1, cursor.line + max_lines, false)
  table.insert(lines_after, 1, cur_line_after)
  local after = table.concat(lines_after, '\n')

  local service = conf:get('provider')
  service:complete(before, after, function(data)
    self:end_complete(data, ctx, cb)
  end)
end

--- complete
function Source:complete(ctx, callback)
  if conf:get('ignored_file_types')[vim.bo.filetype] then
    callback()
    return
  end

  -- Store completion context
  completion_state.self = self
  completion_state.ctx = ctx
  completion_state.callback = callback

  -- Clear existing timer if any
  if completion_state.timer then
    completion_state.timer:stop()
    completion_state.timer:close()
  end

  -- Create new timer
  completion_state.timer = vim.loop.new_timer()
  
  -- Start timer with debounce delay
  completion_state.timer:start(
    conf:get('debounce_delay'),
    0,
    vim.schedule_wrap(function()
      -- Only proceed if we still have valid completion context
      if completion_state.self and completion_state.ctx and completion_state.callback then
        self:_do_complete(completion_state.ctx, completion_state.callback)
      end
      
      -- Cleanup timer
      if completion_state.timer then
        completion_state.timer:close()
        completion_state.timer = nil
      end
    end)
  )
end

function Source:end_complete(data, ctx, cb)
  local items = {}
  for _, response in ipairs(data) do
    local prefix = string.sub(ctx.context.cursor_before_line, ctx.offset)
    local result = prefix .. response
    table.insert(items, {
      cmp = {
        kind_hl_group = 'CmpItemKind' .. conf:get('provider').name,
        kind_text = conf:get('provider').name,
      },
      label = result,
      documentation = {
        kind = cmp.lsp.MarkupKind.Markdown,
        value = '```' .. (vim.filetype.match({ buf = 0 }) or '') .. '\n' .. result .. '\n```',
      },
    })
  end
  cb({
    items = items,
    isIncomplete = conf:get('run_on_every_keystroke'),
  })
end

return Source
