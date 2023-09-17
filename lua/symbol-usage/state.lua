---@alias GlobalState table<integer, Worker[]>

---@type GlobalState
local state = {}

---Add or update data for buffer
---@param bufnr integer Buffer id
---@param worker Worker
function state.add_worker(bufnr, worker)
  if not state[bufnr] then
    state[bufnr] = { worker }
  else
    table.insert(state[bufnr], worker)
  end
end

---Get workers for buffer
---@param buf integer Buffer id
---@return Worker[]
function state.get(buf)
  return state[buf]
end

---Remove data for buffer
---@param bufnr integer Buffer id
function state.remove_buffer(bufnr)
  state[bufnr] = nil
end

return state
