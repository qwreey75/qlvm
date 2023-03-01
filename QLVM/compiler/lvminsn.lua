
--[[
    # Author        : Qwreey / qwreey75@gmail.com / github:qwreey75
    # Create Time   : 2023-02-27 01:53:53
    # Modified by   : Qwreey
    # Modified time : 2023-02-27 02:44:41
    # Description   : |
        Time format = yyy-mm-dd hh:mm:ss
        Time zone = GMT+9
        insn 핸들 (OP, A, B, C 읽기)

        FORKED FROM https://github.com/uniquadev/LuauVM
 ]]

 ---@diagnostic disable-next-line
local bit = (bit32 or bit or require("bit"))

local band = bit.band
local rshift = bit.rshift

-- macros
local function SIGNED_INT(int)
    return int - (2 ^ 32)
end

-- retrive instruction opcode
local function LUAU_INSN_OP(inst)
    return band(inst, 0xff)
end

-- ABC encoding: three 8-bit values, containing registers or small numbers
local function LUAU_INSN_A(insn)
    return band(rshift(insn, 8), 0xff)
end
local function LUAU_INSN_B(insn)
    return band(rshift(insn, 16), 0xff)
end
local function LUAU_INSN_C(insn)
    return band(rshift(insn, 24), 0xff)
end

-- AD encoding: one 8-bit value, one signed 16-bit value
local function LUAU_INSN_D(insn)
    local s = SIGNED_INT(insn)
    local r =  rshift(s, 16) -- ty luau
    -- negative
    if rshift(r, 15) ~= 0 then
    -- if bit32.btest(rshift(r, 15)) then
        return r - 0x10000
    end
    -- position
    return r
end

-- E encoding: one signed 24-bit value
local function LUAU_INSN_E(insn)
    return rshift(SIGNED_INT(insn), 8)
end

-- local function new_upval(stack, id)
--     return {
--         id = id,
--         stack = stack,
--         v = stack[id]
--     };
-- end
-- local function luaF_findupval(state, id)
--     local open_list = state.open_list;
--     local uv = open_list[id];
--     if uv then
--         uv.v = state.stack[id];
--         return uv;
--     end
--     uv = new_upval(state.stack, id);
--     open_list[id] = uv;
--     return uv;
-- end

-- local function luaF_close(state:lobject.ClosureState, level:number)
--     local open_list = state.open_list;
--     for i, uv in pairs(open_list) do
--         if uv.id >= level then
--             uv.v = uv.stack[uv.id];
--             uv.stack = uv;
--             uv.id = 'v';
--             open_list[i] = nil;
--         end
--     end
-- end

-- local function luaG_getline(proto:lobject.Proto, pc:number) : number
local function luaG_getline(proto, pc)
    local lineinfo = proto.lineinfo
    if lineinfo == nil then
        return 0
    end
    return proto.lineinfo[proto.absoffset + rshift(pc, proto.linegaplog2)] + proto.lineinfo[pc-1]
end

return {
    SIGNED_INT = SIGNED_INT;
    LUAU_INSN_OP = LUAU_INSN_OP;
    LUAU_INSN_A = LUAU_INSN_A;
    LUAU_INSN_B = LUAU_INSN_B;
    LUAU_INSN_C = LUAU_INSN_C;
    LUAU_INSN_D = LUAU_INSN_D;
    LUAU_INSN_E = LUAU_INSN_E;
    luaG_getline = luaG_getline;
}
