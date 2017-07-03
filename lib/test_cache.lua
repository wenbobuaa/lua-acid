local cache = require("acid.cache")

function test.proc_cache(t)
    local shared_data = {}

    local func = function(val, err, errmsg)
        return val, err, errmsg
    end

    local cases = {
        {
            args = {shared_data, 'key1', func, {args={'v1', nil, nil}}},
            ret = {'v1', nil, nil},
        },
        {
            args = {shared_data, 'key2', func, {args={nil, 'RuntimeError', ''}}},
            ret = {nil, 'RuntimeError', ''},
        },
    }

    for _, case in ipairs(cases) do
        local val, err, errmes = cache.cacheable(unpack(case.args))
        t:eqlist({val, err, errmes}, case.ret, '')
    end
end

function test.ngx_shdict_cache(t)
    local shared_data = ngx.shared.test_shared

    local func = function(val, err, errmsg)
        return val, err, errmsg
    end

    local cases = {
        {
            args = {shared_data, 'key1', func, {args={'v1', nil, nil}}},
            ret = {'v1', nil, nil},
        },
        {
            args = {shared_data, 'key2', func, {args={nil, 'RuntimeError', ''}}},
            ret = {nil, 'RuntimeError', ''},
        },
    }

    for _, case in ipairs(cases) do
        local val, err, errmes = cache.cacheable(unpack(case.args))
        t:eqlist({val, err, errmes}, case.ret, '')
    end
end

function test.custom_accessor(t)
    local shrd = {}

    local call_times= {
        get = 0,
        set = 0,
        func = 0,
    }

    local func = function()
        call_times.func = call_times.func + 1
        return "value", nil, nil
    end

    local accessor = {
        get = function(dict, key, opts)
            call_times.get = call_times.get + 1
            return dict[key]
        end,
        set = function(dict, key, val, opts)
            dict[key] = val
            call_times.set = call_times.set + 1
            return val
        end,
    }

    local opts = {
        accessor = accessor,
    }

    local rst, err, errmes = cache.cacheable(shrd, "key", func, opts)
    t:eqlist({rst, err, errmes}, {"value", nil, nil})

    t:eqdict(call_times, {get = 2, set = 1, func = 1})
end

function test.release_shared_lock(t)
    local shrd = {}

    local call_times= {
        func = 0,
    }

    local func = function()
        call_times.func = call_times.func + 1
        return "value", nil, nil
    end

    local opts = {
        flush = true,
    }

    local rst, err, errmes = cache.cacheable(shrd, "key", func, opts)
    t:eqlist({rst, err, errmes}, {"value", nil, nil})

    local t0 = ngx.now()

    local rst, err, errmes = cache.cacheable(shrd, "key", func, opts)
    local ts = ngx.now() - t0
    t:eqlist({rst, err, errmes}, {"value", nil, nil})

    t:eq(ts<1, true)
    t:eqlist({rst, err, errmes}, {"value", nil, nil})
    t:eqdict(call_times, {func = 2})
end

function test.lock_timeout(t)
    local shrd = {}

    local func = function(sleep_ts)
        if sleep_ts ~= nil then
            ngx.sleep(sleep_ts)
        end
        return "value", nil, nil
    end

    local cache = require("acid.cache")

    local co1 = ngx.thread.spawn(cache.cacheable, shrd, "key", func, {args={2}})
    local co2 = ngx.thread.spawn(cache.cacheable, shrd, "key", func, {lock_timeout=1})

    local ok, rst, err, errmes = ngx.thread.wait( co2 )
    t:eq(err, 'LockTimeout')
end
