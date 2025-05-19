AddCSLuaFile()

local mt = {}
mt.__index = mt

-- Static array
local function default_copier(x,y) return y end
local function default_constructor() return 0 end
local function static_array(max, constructor, copier)

    local v = { num = 0, max = max, copier = copier or default_copier }
    constructor = constructor or default_constructor
    for i=1, max do v[i] = constructor(i) end
    return setmetatable(v, mt)

end

function mt:sort(func) 

    -- Requires shadow allocation at the moment
    local shadow = {}
    for i=1, self.num do shadow[i] = self[i] end
    table.sort(shadow, func)
    for i=1, self.num do self[i] = shadow[i] end

end
function mt:size() return self.num end
function mt:is_empty() return self.num == 0 end
function mt:is_full() return self.num == self.max end
function mt:reset() self.num = 0 return self end
function mt:reserve(n)

    assert(n <= self.max)
    self.num = n

end

function mt:emplace()

    assert(self.num < self.max)
    self.num = self.num + 1
    return self[self.num]

end

function mt:add(v)

    assert(self.num < self.max, "array overflow")
    self.num = self.num + 1
    self[self.num] = self.copier(self[self.num], v)
    return self.num

end

function mt:copy_into(other)

    assert(other.max == self.max, "arrays don't match")
    other.num = self.num
    for i=1, self.num do 
        other[i] = self.copier(other[i], self[i]) 
    end

end

-- Priority queue (wraps around static_array)
-- Does not have any intrinsic state, just heapifies static_array
-- Based on https://github.com/luapower/heap/blob/master/heap.lua 
-- (Original written by Cosmin Apreutesei. public domain)
local mt = {}
local floor = math.floor
mt.__index = mt

function mt:rebalance(i) if self.move_up(i) == i then self.move_down(i) end end
function mt:push(v) return self.move_up(self.array:add(v)) end
function mt:pop() return self.pop_func() end
function mt:peek() return self.array[1] end
function mt:size() return self.array.num end
function mt:is_empty() return self.array.num == 0 end
function mt:reset() self.array:reset() end

local function default_less(a,b) return a < b end
local function static_pqueue(array, cmp)

    cmp = cmp or default_less

    local function move_up(child)

        local parent = floor(child / 2)
        while child > 1 and cmp(array[child], array[parent]) do
            array[child], array[parent] = array[parent], array[child]
            child, parent = parent, floor(parent / 2)
        end
        return child

    end

    local function move_down(parent)

        local child, num = parent * 2, array.num
        while child <= num do
            if child < num and cmp(array[child + 1], array[child]) then 
                child = child + 1 
            end
            if not cmp(array[child], array[parent]) then break end
            array[child], array[parent] = array[parent], array[child]
            child, parent = child * 2, child
        end
        return parent

    end

    local function pop_func()

        if array.num == 0 then return nil end
        local v = array[1]
        array[1], array[array.num] = array[array.num], array[1]
        array.num = array.num - 1
        move_down(1)
        return v

    end

    return setmetatable({
        array = array,
        move_down = move_down,
        move_up = move_up,
        pop_func = pop_func,
    }, mt)

end

return {
    array = static_array,
    pqueue = static_pqueue,
}