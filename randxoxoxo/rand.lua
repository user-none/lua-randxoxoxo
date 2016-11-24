-- Copyright (c) 2016 John Schember <john@nachtimwald.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the "Software"),
-- to deal in the Software without restriction, including without limitation
-- the rights to use, copy, modify, merge, publish, distribute, sublicense,
-- and/or sell copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
-- DEALINGS IN THE SOFTWARE.

--- Random number module.
--
-- Produces unsigned 64 bit random numbers.
--
-- Uses the xoroshiro128+ algorithm by David Blackman and Sebastiano Vigna.

local os = require("os")
local u64 = require("nums.uintb").u64

local M = {}
local M_mt = { __metatable = {}, __index = M }

--- Maximum random number that can be generated.
M.RAND_MAX = u64("0xFFFFFFFFFFFFFFFF")

--- Mixes a number.
local function splitmix64(n)
    n = u64(n)
    n = n + u64("0x9E3779B97F4A7C15")
    n = (n ~ (n >> 30)) * u64("0xBF58476D1CE4E5B9")
    n = (n ~ (n >> 27)) * u64("0x94D049BB133111EB")
    n = n ~ (n >> 31)
    return n
end

local function rotate_left(x, n)
    return (x << n) | (x >> (64-n))
end

--- Create a random number state object.
--
-- @param seed Optional starting seed which can be used
--             to generate a known sequence.
--
-- @return random state object.
function M:new(seed)
    local n1
    local n2

    if self ~= M then
        return nil, "First argument must be self"
    end
    local o = setmetatable({}, M_mt)

    if seed == nil then
        seed = u64(0)
    else
        seed = u64(seed)
    end

    -- If a seed was not provided try to generate one using
    -- some hopefully random enough data we have available.
    -- We're going to do the best we can to make it so two
    -- calls to new at the same time won't end up with the
    -- same seed.
    if seed == u64(0) then
        n1 = u64(tostring({}):gsub("^.* ", ""))
        n2 = u64(tostring(splitmix64):gsub("^.* ", ""))
        seed = (u64(os.time(os.date("!*t"))) << 20) ~ ((n1 << 32) | n2)
    else
        seed = u64(seed)
    end

    o._state = { splitmix64(seed), seed }
    return o
end
setmetatable(M, { __call = M.new })

--- Duplicate a random number state
--
-- @return random state object.
function M:copy()
    local o = M:new(1)
    o._state[1] = self._state[1]:copy()
    o._state[2] = self._state[2]:copy()
    return o
end

--- Advance in the sequence to allow for reuse of the same seed
-- to allow parallel non-overlapping sequences.
function M:jump()
    local s0 = u64(0)
    local s1 = u64(0)
    local JUMP = { u64("0xBEAC0467EBA5FACB"), u64("0xD86B048B86AA9922") }

    for _,j in ipairs(JUMP) do
        for b=0,63 do
            if j & (u64(1) << b) ~= u64(0) then
                s0 = s0 ~ self._state[1]
                s1 = s1 ~ self._state[2]
            end
            self:rand()
        end
    end

    self._state[1] = s0
    self._state[2] = s1
end

--- Generate a random number
--
-- @return u64 number.
function M:rand()
    local s0
    local s1
    local ret

    s0 = self._state[1]
    s1 = self._state[2]
    ret = s0 + s1

    s1 = s1 ~ s0
    self._state[1] = rotate_left(s0, 55) ~ s1 ~ (s1 << 14)
    self._state[2] = rotate_left(s1, 36)

    return ret
end

--- Generate a random number in a given range.
--
-- Range is determined by [min, max)
--
-- @return u64 number.
function M:rand_range(min, max)
    local range
    local ret
    local r

    min = u64(min)
    max = u64(max)

    if min == max then
        return min:copy()
    end
    if min > max then
        return u64(0)
    end

    -- Range reduction is done by dividing into a number of same size
    -- buckets where each bucket represents a number in the range. You could
    -- mod the result of :rand but mod introduces bias. This might not matter
    -- since this a pseudo random number generator but this unbiased reduction
    -- function is provided anyway.
    --
    -- Not all ranges can be divided into an even number of same size buckets.
    -- When this happens the last bucket will act as catch, and if the random
    -- number falls within that bucket we try again. Also, integer division is
    -- used which will truncate. So the last bucket can be larger than the others.
    --
    -- For example:
    --
    -- RAND_MAX = 100, min = 5, max = 32. The range is 27. 100/27 is 3 so we
    -- have groups of 3 numbers for each bucket. 100/27 is really 3.7... but
    -- we're using integer division and this guarantees we'll have at least
    -- range number of equal size buckets. We actually end up with 33 bucks but
    -- we'll ignore the remainder because we only care about the ones within
    -- our range.
    -- 
    -- [0,2] = 0
    -- [3,5] = 1
    -- ...
    -- [79,80] = 26
    -- [81,100] = Try again.
    range = max - min
    r = self:rand()
    -- Check is r falls in the tail.
    if r >= M.RAND_MAX - (M.RAND_MAX % range) then
        ret = self:rand_range(min, max)
    else
        -- Get the bucket index that corresponds to our reduced number and add
        -- min to bring it into the requested range.
        ret = min + (r / (M.RAND_MAX / range))
    end

    return ret
end

return M
