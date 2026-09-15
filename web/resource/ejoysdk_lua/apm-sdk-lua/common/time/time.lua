-- port from golang: https://golang.org/src/time/time.go
--

local secondsPerMinute = 60
local secondsPerHour   = 60 * 60
local secondsPerDay    = 24 * secondsPerHour
local secondsPerWeek   = 7 * secondsPerDay
local daysPer400Years  = 365*400 + 97
local daysPer100Years  = 365*100 + 24
local daysPer4Years    = 365*4 + 1

local unixBase = (1969*365 + math.floor(1969/4) - math.floor(1969/100) + math.floor(1969/400)) * secondsPerDay

-- daysBefore[m] counts the number of days in a non-leap year
-- before month m begins. There is an entry for m=12, counting
-- the number of days before January of next year (365).
local daysBefore = {
                0,
                31,
                31 + 28,
                31 + 28 + 31,
                31 + 28 + 31 + 30,
                31 + 28 + 31 + 30 + 31,
                31 + 28 + 31 + 30 + 31 + 30,
                31 + 28 + 31 + 30 + 31 + 30 + 31,
                31 + 28 + 31 + 30 + 31 + 30 + 31 + 31,
                31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30,
                31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31,
                31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31 + 30,
                31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31 + 30 + 31,
}

-- local January   = 1
local February  = 2
local March     = 3
-- local April     = 4
-- local May       = 5
-- local June      = 6
-- local July      = 7
-- local August    = 8
-- local September = 9
-- local October   = 10
-- local November  = 11
-- local December  = 12

-- local Sunday    = 1
-- local Monday    = 2
-- local Tuesday   = 3
-- local Wednesday = 4
-- local Thursday  = 5
-- local Friday    = 6
-- local Saturday  = 7

-- absTimestamp returns the absolute second from {year=1, month=1, day=1, hour=0, mintue=0, second=0}
local function absTimestamp(ts)
    return ts + unixBase
end

local function isLeap(year)
    return year%4 == 0 and (year%100 ~= 0 or year%400 == 0)
end

-- convert timestamp to weekday
local function absWeekday(abs)
    -- January 1 of the absolute year, like January 1 of 2001, was a Monday.
    local sec = (abs+1*secondsPerDay) % secondsPerWeek
    return math.floor(sec / secondsPerDay) + 1
end

-- convert timestamp to year, month, day, yday
local function absDate(abs)
    local day = math.floor(abs / secondsPerDay)

    local n, y
    -- Account for 400 year cycles.
    n = math.floor(day / daysPer400Years)
    y = 400 * n
    day = day - daysPer400Years * n

    -- Cut off 100-year cycles.
    -- The last cycle has one extra leap year, so on the last day
    -- of that year, day / daysPer100Years will be 4 instead of 3.
    -- Cut it back down to 3 by subtracting n>>2.
    n = math.floor(day / daysPer100Years)
    n = n - math.floor((n / 4))
    y = y + 100 *n
    day = day - daysPer100Years * n

    -- Cut off 4-year cycles.
    -- The last cycle has a missing leap year, which does not
    -- affect the computation.
    n = math.floor(day / daysPer4Years)
    y = y + 4 * n
    day = day - daysPer4Years * n

    -- Cut off years within a 4-year cycle.
    -- The last year is a leap year, so on the last day of that year,
    -- day / 365 will be 4 instead of 3. Cut it back down to 3
    -- by subtracting n>>2.
    n = math.floor(day / 365)
    n = n - math.floor((n / 4))
    y = y + n
    day = day - 365 * n

    local year = y + 1
    local yday = day + 1

    if isLeap(year) then
        -- Leap year
        if day > 31+29-1 then
            -- After leap day; pretend it wasn't there.
            day = day - 1
        elseif day == 31+29-1 then
            return year, February, 29, yday
        end
    end

    -- Estimate month on assumption that every month has 31 days.
    -- The estimate may be too low by at most one month, so adjust.
    local month = math.floor(day / 31) + 1
    local monthDayEnd = daysBefore[month + 1]
    local monthDayBegin

    if day >= monthDayEnd then
        month = month + 1
        monthDayBegin = monthDayEnd
    else
        monthDayBegin = daysBefore[month]
    end

    day = day - monthDayBegin + 1
    return year, month, day, yday
end

local function absDayFromDate(t)
    local y = assert(t.year, "year") - 1
    local day = y*365 + math.floor(y/4) - math.floor(y/100) + math.floor(y/400)

    if t.yday then
        day = day + t.yday - 1
    else
        local m = assert(t.month, "month")
        local d = assert(t.day, "day")

        day = day + daysBefore[m]
        if isLeap(t.year) and m >= March then
            -- February 29
            day = day + 1
        end

        -- Add in days before today.
        day = day + d - 1
    end
    return day
end

local M = {}

M.TZ = 8

-- table格式转成时间戳
function M.time(t)
    local day = absDayFromDate(t)
    local timestamp = day * secondsPerDay
    if t.hour then
        timestamp = timestamp + t.hour * secondsPerHour + t.min * secondsPerMinute + t.sec
    end
    return timestamp - unixBase
end

-- 指定时区的table格式转成时间戳
function M.utctime(t, tz)
    tz = tz or M.TZ
    return M.time(t) - tz * secondsPerHour
end

-- 时间戳转换成table格式
function M.date(sec, t)
    assert(sec)
    local abs = absTimestamp(sec)
    t = t or {}
    t.year, t.month, t.day, t.yday = absDate(abs)
    t.wday = absWeekday(abs)

    local seconds = abs % secondsPerDay
    t.hour = math.floor(seconds / secondsPerHour)
    seconds = seconds - (t.hour * secondsPerHour)
    t.min = math.floor(seconds / secondsPerMinute)
    t.sec = seconds - (t.min * secondsPerMinute)
    return t
end

-- 指定时区的时间戳转换成table格式
function M.localdate(sec, tz, t)
    tz = tz or M.TZ
    return M.date(sec + tz*secondsPerHour, t)
end

-- 时间戳转换成字符串
local tmp = {}
function M.format(sec, utc)
    if utc then
        M.date(sec, tmp)
    else
        M.localdate(sec, nil, tmp)
    end

    return string.format("%4d-%02d-%02d %02d:%02d:%02d",
        tmp.year, tmp.month, tmp.day, tmp.hour, tmp.min, tmp.sec)
end

-- 字符串格式转换成table格式
-- str: 2014-04-02 13:15:26
-- ret: {year=2014, month=4, day=2, hour=13, min=15, sec=26}
function M.parse(str)
    if not str then
        return
    end

    local year, month, day, hour, min, sec
    if str:find(":") then
        year, month, day, hour, min, sec = str:match("([%d]+)-([%d]+)-([%d]+) ([%d]+):([%d]+):([%d]+)")
    else
        year, month, day = str:match("([%d]+)-([%d]+)-([%d]+)")
        hour = 0
        min  = 0
        sec  = 0
    end
    if not (year and month and day and hour and min and sec) then
        return nil
    end
    local t = {
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec)
    }
    return t
end

return M