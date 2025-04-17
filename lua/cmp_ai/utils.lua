local M = {}

-- Stores timer handles for each unique debounce key
local timers = {}

---@param key string A unique key to identify this debounce instance
---@param fn function The function to debounce
---@param timeout number Time in milliseconds to wait before executing
function M.debounce(key, fn, timeout)
  -- Clear existing timer if any
  if timers[key] then
    timers[key]:stop()
    timers[key]:close()
  end

  -- Create new timer
  timers[key] = vim.loop.new_timer()
  
  -- Start timer with the specified timeout
  timers[key]:start(timeout, 0, vim.schedule_wrap(function()
    -- Clear the timer reference
    timers[key]:close()
    timers[key] = nil
    -- Execute the debounced function
    fn()
  end))
end

return M 