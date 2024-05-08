local u = require('symbol-usage.utils')
---@alias GlobalState table
---@alias Buffers table<integer, Worker[]>

---@type GlobalState
local state = {}

---@type boolean
state.active = true
---@type Buffers
state.buffers = {}

---Add or update data for buffer
---@param bufnr integer Buffer id
---@param worker Worker
---@return boolean True if worker was added
function state.add_worker(bufnr, worker)
  if not state.buffers[bufnr] then
    state.buffers[bufnr] = { worker }
  else
    -- avoid duplicates workers
    if u.some(state.buffers[bufnr], function(v)
      return v.client.id == worker.client.id
    end) then
      return false
    end
    table.insert(state.buffers[bufnr], worker)
  end

  return true
end

---Get workers for buffer
---@param buf integer Buffer id
---@return Worker[]
function state.get_buf_workers(buf)
  return state.buffers[buf] or {}
end

---Remove data for buffer
---@param bufnr integer Buffer id
function state.remove_buffer(bufnr)
  state.buffers[bufnr] = nil
end

function state.clear_buffers()
  state.buffers = {}
end

return state
