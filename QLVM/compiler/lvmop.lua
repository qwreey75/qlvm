local bytecode = require("QLVM/compiler/lvmbytecode")
local lvminsn = require("QLVM/compiler/lvminsn")

local LuauOpcode = bytecode.LuauOpcode
local LuauCaptureType = bytecode.LuauCaptureType
local insert = table.insert
local concat = table.concat

-- local SIGNED_INT = lvminsn.SIGNED_INT
-- local LUAU_INSN_OP = lvminsn.LUAU_INSN_OP
local LUAU_INSN_A = lvminsn.LUAU_INSN_A
local LUAU_INSN_B = lvminsn.LUAU_INSN_B
local LUAU_INSN_C = lvminsn.LUAU_INSN_C
local LUAU_INSN_D = lvminsn.LUAU_INSN_D
-- local LUAU_INSN_E = lvminsn.LUAU_INSN_E

local OP_TO_CALL = {}

-- 코드 추가
local function append(qlvm_state,...)
    local packed = table.pack(...)
    insert(qlvm_state.gen,concat(packed,"",1,qlvm_state.n))
    insert(qlvm_state.gen,qlvm_state.newline)
end

-- 코드 위치 변경
local function addpos(qlvm_state,offset)
    if not offset then offset = 1 end
    qlvm_state.position = qlvm_state.position + offset
end

-- 리지스터 id 를 가지고 변수 읽어오는 코드를 생성
local function registerToNamespace(qlvm_state,id)
    local namespace = qlvm_state.stackNamespace[id]

    -- 업밸류가 있어 테이블로 값을 감싼 상태임
    -- register = {register} 되어 있으므로 값을
    -- register[1] 로 내보내야함
    if qlvm_state.registerHasUpvalue[id] then
        return namespace .. "[1]"
    end

    return namespace
end

-- 업밸류 id 를 가지고 변수 읽어오는 코드를 생성
local function indexToUpvalue(qlvm_state,ref)
    return table.concat {
        qlvm_state.upvaluerefNamespace,"[",tostring(ref),"][1]"
    }
end

-- constant id 를 가지고 변수 읽어오는 코드를 생성
local function indexToConstant(qlvm_state,id)
    return table.concat{
        qlvm_state.constantTableNamespace,".",qlvm_state.constantNamespace[id]
    }
end

-- aux 를 위한 readinsn 문
local function readinsn(qlvm_state)
    return qlvm_state.proto.code[qlvm_state.position]
end

-- NOP: noop
OP_TO_CALL[LuauOpcode.LOP_NOP] = function(qlvm_state)
    addpos(qlvm_state)
end

-- BREAK: debugger break
OP_TO_CALL[LuauOpcode.LOP_BREAK] = OP_TO_CALL[LuauOpcode.LOP_NOP]

-- 값을 nil 값으로
-- LOADNIL: sets register to nil
-- A: target register
OP_TO_CALL[LuauOpcode.LOP_LOADNIL] = function(qlvm_state,insn)
    addpos(qlvm_state)

    -- namespace=nil;
    append(qlvm_state,
        registerToNamespace(
            qlvm_state,LUAU_INSN_A(insn)
        ),"=nil;")
end

-- 값을 boolean 으로
-- LOADB: sets register to boolean and jumps to a given short offset (used to compile comparison results into a boolean)
-- A: target register
-- B: value (0/1)
-- C: jump offset
OP_TO_CALL[LuauOpcode.LOP_LOADB] = function(qlvm_state,insn)
    addpos(qlvm_state,LUAU_INSN_C(insn) + 1)

    -- namespace=true/false;
    append(qlvm_state,
        registerToNamespace(
            qlvm_state,LUAU_INSN_A(insn)
        ),"=",
        tostring(LUAU_INSN_B(insn) ~= 0),";")
end

-- 값을 number 로
-- LOADN: sets register to a number literal
-- A: target register
-- D: value (-32768..32767)
OP_TO_CALL[LuauOpcode.LOP_LOADN] = function(qlvm_state,insn)
    addpos(qlvm_state)

    -- namespace=1;
    append(qlvm_state,
        registerToNamespace(
            qlvm_state,LUAU_INSN_A(insn)
        ),"=",
        tostring(LUAU_INSN_D(insn)),";")
end

-- 상수 (문자열 ...) 불러오기
-- LOADK: sets register to an entry from the constant table from the proto (number/string)
-- A: target register
-- D: constant table index (0..32767)
-- TODO: 문자열 난독화를 위해 constant (k) 측에서 변경 필요
OP_TO_CALL[LuauOpcode.LOP_LOADK] = function(qlvm_state,insn)
    addpos(qlvm_state)

    -- namespace=knamespace;
    append(qlvm_state,
        registerToNamespace(
            qlvm_state,LUAU_INSN_A(insn)
        ),"=",
        indexToConstant(
            qlvm_state,LUAU_INSN_D(insn)
        ),";")
end

-- 값 이동
-- MOVE: move (copy) value from one register to another
-- A: target register
-- B: source register
OP_TO_CALL[LuauOpcode.LOP_MOVE] = function(qlvm_state,insn)
    addpos(qlvm_state)

    -- target=source;
    append(qlvm_state,
        registerToNamespace(
            qlvm_state,LUAU_INSN_A(insn)
        ),"=",
        registerToNamespace(
            qlvm_state,LUAU_INSN_B(insn)
        ),";")
end

-- 글로벌 값 불러오기
-- GETGLOBAL: load value from global table using constant string as a key
-- A: target register
-- C: predicted slot index (based on hash)
-- AUX: constant table index
OP_TO_CALL[LuauOpcode.LOP_GETGLOBAL] = function(qlvm_state,insn)
    addpos(qlvm_state)
    local aux = readinsn(qlvm_state)
    addpos(qlvm_state)

    -- 네임스페이스 끌고옴
    local target = registerToNamespace(
        qlvm_state,LUAU_INSN_A(insn)
    )

    -- constant 네임스페이스 끌고옴 (글로벌 이름)
    local globalName = indexToConstant(qlvm_state,aux)

    -- namespace=env[name]
    append(qlvm_state,
        target,"=",qlvm_state.envNamespace,"[",globalName,"]",";")
end

-- 글로벌 값 설정
-- SETGLOBAL: set value in global table using constant string as a key
-- A: source register
-- C: predicted slot index (based on hash)
-- AUX: constant table index
OP_TO_CALL[LuauOpcode.LOP_SETGLOBAL] = function(qlvm_state,insn)
    addpos(qlvm_state)
    local aux = readinsn(qlvm_state)
    addpos(qlvm_state)

    -- 네임스페이스 끌고옴
    local target = registerToNamespace(
        qlvm_state,LUAU_INSN_A(insn)
    )

    -- constant 네임스페이스 끌고옴
    local globalName = indexToConstant(qlvm_state,aux)

    -- env[name]=namespace
    append(qlvm_state,
        qlvm_state.envNamespace,"[",globalName,"]=",target,";")
end

-- Upvalue 가져오기
-- GETUPVAL: load upvalue from the upvalue table for the current function
-- A: target register
-- B: upvalue index (0..255)
OP_TO_CALL[LuauOpcode.LOP_GETUPVAL] = function(qlvm_state,insn)
    addpos(qlvm_state)

    append(qlvm_state,
        registerToNamespace(
            qlvm_state,LUAU_INSN_A(insn)
        ),"=",
        indexToUpvalue(qlvm_state,LUAU_INSN_B(insn)),";")
end

-- Upvalue 설정하기
-- SETUPVAL: store value into the upvalue table for the current function
-- A: target register
-- B: upvalue index (0..255)
OP_TO_CALL[LuauOpcode.LOP_SETUPVAL] = function(qlvm_state,insn)
    addpos(qlvm_state)

    local target = registerToNamespace(
        qlvm_state,LUAU_INSN_A(insn)
    )
    local ref = LUAU_INSN_B(insn)

    append(qlvm_state,
        indexToUpvalue(qlvm_state,ref),"=",target
    )

    append(qlvm_state,
        indexToUpvalue(qlvm_state,LUAU_INSN_B(insn)),"=",
        registerToNamespace(
            qlvm_state,LUAU_INSN_A(insn)
        ),";")
end

-- TODO: idk i need to write this
-- CLOSEUPVALS: close (migrate to heap) all upvalues that were captured for registers >= target
-- A: target register
OP_TO_CALL[LuauOpcode.LOP_CLOSEUPVALS] = function(qlvm_state,insn)
    addpos(qlvm_state)

    -- local target = LUAU_INSN_A(insn);
    -- luaF_close(state, target);
    -- NOTING TO DO...
end

-- GETIMPORT: load imported global table global from the constant table
-- A: target register
-- D: constant table index (0..32767); we assume that imports are loaded into the constant table
-- AUX: 3 10-bit indices of constant strings that, combined, constitute an import path; length of the path is set by the top 2 bits (1,2,3)
OP_TO_CALL[LuauOpcode.LOP_GETIMPORT] = function(qlvm_state,insn)
    addpos(qlvm_state,2) -- skip aux instruction

    local kv = qlvm_state.constantNamespace[LUAU_INSN_D(insn)]

    if kv then
        append(qlvm_state,
            registerToNamespace(
                qlvm_state,LUAU_INSN_A(insn)
            ),"=",
            indexToConstant(
                qlvm_state,LUAU_INSN_D(insn)
            ),";")
    else
        print("ERROR: not cached getimport call")
    --     local aux = state.proto.code[state.pc];
    --     state.pc += 1;
    --     local res = table.pack(
    --         pcall(resolve_import, state.env, state.proto.k, aux)
    --     );
    --     -- check integrity and store import to stack
    --     if res[1] then
    --         state.stack[id] = res[2];
    --     end;
    end
end

-- GETTABLE: load value from table into target register using key from register
-- A: target register
-- B: table register
-- C: index register
OP_TO_CALL[LuauOpcode.LOP_GETTABLE] = function(qlvm_state,insn)
    addpos(qlvm_state)

    -- state.stack[id] = state.stack[id2][state.stack[idx]]
    append(qlvm_state,
        registerToNamespace(
            qlvm_state,LUAU_INSN_A(insn)
        ),"=",
        registerToNamespace(
            qlvm_state,LUAU_INSN_B(insn)
        ),"[",
        registerToNamespace(
            qlvm_state,LUAU_INSN_C(insn)
        ),"];")
end

-- SETTABLE: store source register into table using key from register
-- A: source register
-- B: table register
-- C: index register
OP_TO_CALL[LuauOpcode.LOP_SETTABLE] = function(qlvm_state,insn)
    addpos(qlvm_state)

    -- local src = state.stack[LUAU_INSN_A(insn)]
    -- local tbl = state.stack[LUAU_INSN_B(insn)]
    -- local idx = state.stack[LUAU_INSN_C(insn)]
    -- tbl[idx] = src
    append(qlvm_state,
        registerToNamespace(
            qlvm_state,LUAU_INSN_B(insn)
        ),"[",
        registerToNamespace(
            qlvm_state,LUAU_INSN_C(insn)
        ),"]=",
        registerToNamespace(
            qlvm_state,LUAU_INSN_A(insn)
        ),";")
end

-- GETTABLEKS: load value from table into target register using constant string as a key
-- A: target register
-- B: table register
-- C: predicted slot index (based on hash)
-- AUX: constant table index
OP_TO_CALL[LuauOpcode.LOP_GETTABLEKS] = function(qlvm_state,insn)
    addpos(qlvm_state)
    local aux = readinsn(qlvm_state)
    addpos(qlvm_state)

    -- local id = LUAU_INSN_A(insn)
    -- local t = state.stack[LUAU_INSN_B(insn)]
    -- local hash = LUAU_INSN_C(insn)

    -- local aux = state.proto.code[state.pc]
    -- state.pc += 1

    -- local kv = state.proto.k[aux]
    -- state.stack[id] = t[kv]

    append(qlvm_state,
        registerToNamespace(
            qlvm_state,LUAU_INSN_A(insn)
        ),"=",
        registerToNamespace(
            qlvm_state,LUAU_INSN_B(insn)
        ),"[",
        indexToConstant(qlvm_state,aux),"];")
end

-- SETTABLEKS: store source register into table using constant string as a key
-- A: source register
-- B: table register
-- C: predicted slot index (based on hash)
-- AUX: constant table index
OP_TO_CALL[LuauOpcode.LOP_SETTABLEKS] = function(qlvm_state,insn)
    addpos(qlvm_state)
    local aux = readinsn(qlvm_state)
    addpos(qlvm_state)

    -- local src = state.stack[LUAU_INSN_A(insn)]
    -- local tbl = state.stack[LUAU_INSN_B(insn)]
    -- local hash = LUAU_INSN_C(insn)
    -- local aux = state.proto.code[state.pc]
    -- state.pc += 1

    -- local idx = state.proto.k[aux]
    -- tbl[idx] = src
    append(qlvm_state,
        registerToNamespace(
            qlvm_state,LUAU_INSN_B(insn)
        ),"[",
        indexToConstant(qlvm_state,aux),"]=",
        registerToNamespace(
            qlvm_state,LUAU_INSN_A(insn)
        ),";")
end

-- GETTABLEN: load value from table into target register using small integer index as a key
-- A: target register
-- B: table register
-- C: index-1 (index is 1..256)
OP_TO_CALL[LuauOpcode.LOP_GETTABLEN] = function(qlvm_state,insn)
    addpos(qlvm_state)

    -- local id = LUAU_INSN_A(insn)
    -- local tbl = state.stack[LUAU_INSN_B(insn)]
    -- local idx = LUAU_INSN_C(insn) + 1
    -- state.stack[id] = tbl[idx]

    append(qlvm_state,
        registerToNamespace(
            qlvm_state,LUAU_INSN_A(insn)
        ),"=",
        registerToNamespace(
            qlvm_state,LUAU_INSN_B(insn)
        ),"[",
        tostring(LUAU_INSN_C(insn) + 1),"];")
end

-- SETTABLEN: store source register into table using small integer index as a key
-- A: source register
-- B: table register
-- C: index-1 (index is 1..256)
OP_TO_CALL[LuauOpcode.LOP_SETTABLEN] = function(qlvm_state,insn)
    addpos(qlvm_state)

    -- local src = state.stack[LUAU_INSN_A(insn)]
    -- local tbl = state.stack[LUAU_INSN_B(insn)]
    -- local idx = LUAU_INSN_C(insn) + 1
    -- tbl[idx] = src

    append(qlvm_state,
        registerToNamespace(
            qlvm_state,LUAU_INSN_B(insn)
        ),"[",
        tostring(LUAU_INSN_C(insn) + 1),"]=",
        registerToNamespace(
            qlvm_state,LUAU_INSN_A(insn)
        ),";")
end

-- 아아 클로저 만들기
-- NEWCLOSURE: create closure from a child proto; followed by a CAPTURE instruction for each upvalue
-- A: target register
-- D: child proto index (0..32767)
OP_TO_CALL[LuauOpcode.LOP_NEWCLOSURE] = function(qlvm_state,insn)
    addpos(qlvm_state)
    print(require("QLVM/inspact")(qlvm_state))
    -- 타겟 프로토타입
    local protoNumber = qlvm_state.proto.p[LUAU_INSN_D(insn)][1]
    local proto = qlvm_state.protos[protoNumber]
    local protoId = qlvm_state.protoIds[protoNumber]

    -- 레지스터를 업벨류로 승격
    local upvaluefiyIndex = {} -- r1,r2,r3,r4
    local upvaluefiyValue = {} -- ={r1},{r2},{r3}
    -- 레퍼런스 테이블
    local refGen = {} -- 내부 클로저에 넘겨줄 테이블

    -- 프로토타입의 업밸류 수에 맞게 CAPTURE 를 따냄
    for i = 0, proto.nups - 1 do
        -- 다음 바이트코드 읽어옴
        local capture = readinsn(qlvm_state)
        addpos(qlvm_state)

        local ctype = LUAU_INSN_A(capture) -- capture type
        local source = LUAU_INSN_B(capture) -- capture id
        if ctype == LuauCaptureType.LCT_VAL or ctype == LuauCaptureType.LCT_REF then
            -- 로컬 캡쳐 / 이미 업밸류 전적 있는 로컬캡쳐
            -- 레지스터를 그냥 테이블로 한번 덮음
            local localName = qlvm_state.stackNamespace[source]
            if not qlvm_state.registerHasUpvalue[source] then
                qlvm_state.registerHasUpvalue[source] = true
                insert(upvaluefiyIndex,localName) -- rn
                insert(upvaluefiyValue,"{"..localName.."}") -- {rn}
            end
            insert(refGen,localName) -- ref table
        elseif ctype == LuauCaptureType.LCT_UPVAL then -- 업밸류에서 읽어옴
            -- 상위 업밸류 키
            insert(refGen,qlvm_state.upvaluerefNamespace
                .. "[" .. (
                    (source == 1 and qlvm_state.namespaceHandler.one) or
                    (source == 2 and qlvm_state.namespaceHandler.two) or
                    (source == 3 and qlvm_state.namespaceHandler.three) or
                    (source == 4 and qlvm_state.namespaceHandler.four) or
                    (source == 5 and qlvm_state.namespaceHandler.five) or
                source) .. "]"
            )
        end
    end

    -- state.stack[id] = wrap_proto(proto, state.env, upsref)
    append(qlvm_state,
        concat(upvaluefiyIndex,","),"=", -- r1,r2,r3
        concat(upvaluefiyValue,","),";",
        registerToNamespace( -- 타겟
            qlvm_state,LUAU_INSN_A(insn) -- target
        ),"=",
        qlvm_state.namespaceHandler.createWrapper, -- 클로저 생성자
        "(",qlvm_state.envNamespace,",{",concat(refGen,","),"},",protoId,");") -- 클로저 인자
end

--[[

OP_TO_CALL[LuauOpcode.LOP_NAMECALL] = function(qlvm_state,insn)
    addpos(qlvm_state)

    local id = LUAU_INSN_A(insn)
    local id2 = LUAU_INSN_B(insn)
    -- local hash = LUAU_INSN_C(insn)
    local aux = state.proto.code[state.pc]
    state.pc += 1

    local t = state.stack[id2]
    local kv = state.proto.k[aux]
    state.stack[id + 1] = t
    state.stack[id] = t[kv]
end

OP_TO_CALL[LuauOpcode.LOP_CALL] = function(qlvm_state,insn)
    addpos(qlvm_state)
    local id = LUAU_INSN_A(insn)

    local nparams = LUAU_INSN_B(insn) - 1
    local nresults = LUAU_INSN_C(insn) - 1
    
    local params = nparams == LUA_MULTRET and state.top - id or nparams
    local ret = table.pack(state.stack[id](table.unpack(state.stack, id + 1, id + params)))
    local nres = ret.n

    if nresults == LUA_MULTRET then
        state.top = id + nres - 1
    else
        state.top = -1
        nres = nresults
    end

    table.move(ret, 1, nres, id, state.stack)
end

OP_TO_CALL[LuauOpcode.LOP_RETURN] = function(qlvm_state,insn)
    local insn = state.insn
    state.run = false
    state.pc += 1

    local id = LUAU_INSN_A(insn)
    local b = LUAU_INSN_B(insn)
    local nresults

    if b == 0 then
        nresults = state.top - id + 1
    else
        nresults = b - 1
    end

    table.move(state.stack, id, id + nresults - 1, 1, state.ret)
end

-- JUMP: jumps to target offset
-- D: jump offset (-32768..32767; 0 means "next instruction" aka "don't jump")
OP_TO_CALL[LuauOpcode.LOP_JUMP] = function(qlvm_state,insn)
    addpos(qlvm_state,LUAU_INSN_D(insn)+1)
end

-- JUMPBACK: jumps to target offset; this is equivalent to JUMP but is used as a safepoint to be able to interrupt while/repeat loops
-- D: jump offset (-32768..32767; 0 means "next instruction" aka "don't jump")
OP_TO_CALL[LuauOpcode.LOP_JUMPBACK] = OP_TO_CALL[LuauOpcode.LOP_JUMP]

-- JUMPIF: jumps to target offset if register is not nil/false
-- A: source register
-- D: jump offset (-32768..32767; 0 means "next instruction" aka "don't jump")
LOP_JUMPIF
OP_TO_CALL[LuauOpcode.LOP_JUMPIFNOT]

OP_TO_CALL[LuauOpcode.LOP_JUMPIFNOT] = function(qlvm_state,insn)
    addpos(qlvm_state)

    local id = LUAU_INSN_A(insn)
    local offset = LUAU_INSN_D(insn)
    if not state.stack[id] then
        state.pc += offset
    end
end
--]]
return OP_TO_CALL
