-- imports
local bytecode = require("QLVM/compiler/lvmbytecode")
local stream = require("QLVM/stream")

local LuauBytecodeTag = bytecode.LuauBytecodeTag

---@diagnostic disable-next-line
local bit = (bit32 or bit or require("bit"))

local bor = bit.bor
local band = bit.band
local bnot = bit.bnot
local lshift = bit.lshift
local rshift = bit.rshift

-- deserialize utils
-- local function readVarInt(st:stream.ByteStream) : number
local function readVarInt(st)
    local result, shift = 0, 0
    local b = 0

    repeat
        b = st:read()
        result = bor(result, lshift(band(b, 127), shift))
        shift = shift + 7
    until band(b, 128) == 0

    return result
end

-- local function read_string(strings:{string}, st:stream.ByteStream) : string?
local function read_string(strings,st)
    local id = readVarInt(st)
    if id == 0 then
        return nil
    end
    return strings[id-1] -- read string id and retrive it from string table
end

local function resolve_import(envt, k, id)
    local count = rshift(id, 30)
    local id0 = count > 0 and band(rshift(id, 20), 1023) or -1
    local id1 = count > 1 and band(rshift(id, 10), 1023) or -1
    local id2 = count > 2 and band(id, 1023) or -1

    local import = {__LUAVMTYPE__="import"}

    table.insert(import,id0)

    if id1 > 0 and import then
        table.insert(import,id1)
    end

    if id2 > 0 and import then
        table.insert(import,id2)
    end

    return import
end

-- return
local function luau_load(data) -- aka lundump.h in Lua 5.x
    local st = stream.new(data)
    local version = st:read()

    if version == 0 then
        error(("main: %s"):format(st.data:sub(2)))
    end

    if version < bytecode.LBC_VERSION_MIN or version > bytecode.LBC_VERSION_MAX then
        error(("main: bytecode version mismatch(expected[%d..%d], got %d"):format(
            bytecode.LBC_VERSION_MIN, bytecode.LBC_VERSION_MAX, version
        ))
    end

    local envt = getfenv()

    -- string table
    local stringCount = readVarInt(st)
    local strings = {}--table.create(stringCount)
    for i=0, stringCount-1 do
        local length = readVarInt(st)
        strings[i] = st.data:sub(st.pos, st.pos + length - 1)
        st.pos = st.pos + length
    end

    -- proto table
    local protoCount = readVarInt(st)
    -- local protos : {lobject.Proto} = table.create(protoCount)
    local protos = {}--table.create(protoCount)
    for i=0, protoCount-1 do
        local maxstacksize = st:read()
        local numparams = st:read()
        local nups = st:read()
        local is_vararg = st:read() ~= 0

        local sizecode = readVarInt(st)
        local code = {}--table.create(sizecode)
        for j=0, sizecode-1 do
            code[j] = st:read_4()
        end

        local sizek = readVarInt(st)
        local k = {}--table.create(sizek)
        for j=0, sizek-1 do
            local tt = st:read() -- constant type
            if tt == LuauBytecodeTag.LBC_CONSTANT_NIL then
                k[j] = nil
            elseif tt == LuauBytecodeTag.LBC_CONSTANT_BOOLEAN then
                k[j] = st:read() ~= 0
            elseif tt == LuauBytecodeTag.LBC_CONSTANT_NUMBER then
                k[j] = st:read_double()
            elseif tt == LuauBytecodeTag.LBC_CONSTANT_STRING then
                k[j] = read_string(strings, st)
            elseif tt == LuauBytecodeTag.LBC_CONSTANT_IMPORT then
                local iid = st:read_4()
                k[j] = resolve_import(envt, k, iid)
            elseif tt == LuauBytecodeTag.LBC_CONSTANT_TABLE then
                local keys = readVarInt(st)
                local t = {}--table.create(keys)
                for _=0, keys-1 do
                    local idx = readVarInt(st)
                    local key = k[idx]
                    t[key] = 0.0
                end
                k[j] = t
            elseif tt == LuauBytecodeTag.LBC_CONSTANT_CLOSURE then
                local fid = readVarInt(st)
                -- k[j] = protos[fid] -- store proto struct to be used later
                k[j] = {__LUAVMTYPE__="closure",fid}
            else
                error(("main: unknown constant type %d"):format(tt))
            end
        end
        -- debug: table.foreach(k, print)
        local sizep = readVarInt(st)

        local p = {}--table.create(sizep)
        for j=0, sizep-1 do
            p[j] = {__LUAVMTYPE__="closure",readVarInt(st)}
            -- p[j] = protos[readVarInt(st)]          -- read proto id and retrive it from proto table
        end

        local linedefined = readVarInt(st)
        local debugname = read_string(strings, st)

        local absoffset, lineinfo, linegaplog2
        -- check if lineinfo is present
        if st:read() ~= 0 then
            linegaplog2 = st:read()

            local intervals = rshift((sizecode - 1), linegaplog2) + 1
            absoffset = band((sizecode + 3), bnot(3))

            local sizelineinfo = absoffset + intervals
            lineinfo = {}--table.create(sizelineinfo)

            local lastoffset = 0
            for j=0, sizecode-1 do
                lastoffset = lastoffset + st:read()
                lastoffset = lastoffset % 256
                lineinfo[j] = lastoffset
            end

            local lastline = 0
            for j=0, intervals-1 do
                lastline = lastline + st:read_4()
                lineinfo[absoffset + j] = lastline
            end
        end

        -- check if debuginfo is present
        local locvars
        local upvalues
        if st:read() ~= 0 then
            local sizelocvars = readVarInt(st)
            locvars = {}--table.create(sizelocvars)

            for j=0, sizelocvars-1 do
                locvars[j] = {
                    varname = read_string(strings, st),
                    startpc = readVarInt(st),
                    endpc = readVarInt(st),
                    reg = st:read()
                }
            end

            local sizeupvalues = readVarInt(st)
            upvalues = {}--table.create(sizeupvalues)

            for j=0, sizeupvalues-1 do
                upvalues[j] = read_string(strings, st)
            end
        end

        -- local proto : lobject.Proto = {
        local proto = {
            __LUAVMTYPE__ = "proto",
            code = code,
            k = k,
            p = p,

            linegaplog2 = linegaplog2,
            absoffset = absoffset,
            lineinfo = lineinfo,

            upvalues = upvalues,
            locvars = locvars,

            debugname = debugname,

            ups = upvalues,
            nups = nups,
            numparams = numparams,
            is_vararg = is_vararg,
            maxstacksize = maxstacksize,
            linedefined = linedefined
        }

        protos[i] = proto
    end

    local mainid = readVarInt(st)
    --print(st.pos, st.size)
    return protos,mainid
end

return {
    luau_load = luau_load,
    resolve_import = resolve_import
}
