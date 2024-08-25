-- stylua: ignore start
-- FIRST SCREEN START
local function one() -- expected text: `1 usage`
  print('one')
end

local function two() -- expected text: `2 usages`
  local function three() end -- expected text with indent: `  1 usage`
  three()
end

local function four()end local function five()end local function six()end -- expected text: `no usage | +2`

one() two() two() six()




-- FIRT SCREEN END

local function seven() end
  local function eight() end
seven()

-- Symbols below should not be counted
local a = 1
local b = 2
local c = {}
-- stylua: ignore end
