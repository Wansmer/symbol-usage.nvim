local u = require('symbol-usage.utils')
---@alias GlobalState table<integer, Worker[]>

---@type GlobalState
local state = {}

---Add or update data for buffer
---@param bufnr integer Buffer id
---@param worker Worker
---@return boolean True if worker was added
function state.add_worker(bufnr, worker)
  if not state[bufnr] then
    state[bufnr] = { worker }
  else
    -- avoid duplicates workers
    if u.some(state[bufnr], function(v)
      return v.client.client_id == worker.client.client_id
    end) then
      return false
    end
    table.insert(state[bufnr], worker)
  end

  return true
end

---Get workers for buffer
---@param buf integer Buffer id
---@return Worker[]
function state.get_buf_workers(buf)
  return state[buf]
end

---Remove data for buffer
---@param bufnr integer Buffer id
function state.remove_buffer(bufnr)
  state[bufnr] = nil
end

return state
