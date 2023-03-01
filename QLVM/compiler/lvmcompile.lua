-- imports
-- local bytecode = require("./QLVM/luau/bytecode")
-- local lvmload = require("./QLVM/luau/lvmload")
-- local lbuiltins = require("./QLVM/luau/lbuiltins")

-- local LuauOpcode = bytecode.LuauOpcode;
-- local LuauCaptureType = bytecode.LuauCaptureType;
-- local get_op_name = bytecode.get_op_name;
-- local resolve_import = lvmload.resolve_import;
-- local fast_functions = lbuiltins.fast_functions;

-- -- constants
-- local LUA_MULTRET = -1;

-- -- globals
-- local OP_TO_CALL = table.create(90);
-- local wrap_proto;
-- local luau_execute;

local lvminsn = require("QLVM/compiler/lvminsn")
local lvmop = require("QLVM/compiler/lvmop")
local lvmconst = require("QLVM/compiler/lvmconst")
local project = require("QLVM/project")

local LUAU_INSN_OP = lvminsn.LUAU_INSN_OP

local function QLVM_compileProto(proto,protos,protoID,protoIds,namespaceHandler)
    -- proto : 이 프로토타입
    -- protoID : 이 프로토타입의 아이디
    -- protoIds : 모든 프로토타입의 아이디를 프로토타입 번호에 맞게 부여한 테이블
    --     protoIds[i]() 가 가능해야함
    -- namespaceHandler : 네임스페이스 생성기
    local qlvm_state = {
        isDebug = project.debug;
        proto = proto;
        protos = protos;
        protoID = protoID;
        protoIds = protoIds;
        namespaceHandler = namespaceHandler;

        -- [리지스터] = true
        -- 리지스터가 업벨류에 의해 핸들링 된다는 소리
        -- 리지스터를 테이블로 다뤄야함
        -- register = {register}
        -- register[1]
        registerHasUpvalue = {}; -- 업벨류 가진 리지스터

        -- 나중에 upvalue ref 를 이걸로 넘겨줍니다
        -- 최적화를 위해서 하고 있는짓임
        -- NEWCLOSURE 가 생성하는 wrap 을 간접적으로 구현할꺼임
        -- 난 워래핑 싫어 ㅇㅅㅇ
        -- [리지스터(함수가담긴)] = {업밸류}
        registerClosure = {}; -- 클로저 담긴 리지스터

        -- 숫자 난독화를 위한 숫자캐시
        numberCache = {};
    }

    -- 라인 브레이커
    qlvm_state.newline = qlvm_state.isDebug and "\n" or ""

    -- 업벨류 네임스페이스
    -- upvaluerefNamespace = { ...[id:number]{ value } }
    qlvm_state.upvaluerefNamespace = namespaceHandler:GetNamespace()

    -- 환경 상태
    -- 글로벌 값 같은게 여기에 설정됨
    qlvm_state.envNamespace = namespaceHandler:GetNamespace()

    -- 스텍 id 당 로컬변수 이름을 반환함
    -- 스텍이 리지스터 목록임
    qlvm_state.stackNamespace = {}
    if proto.maxstacksize > 0 then
        for i=0,proto.maxstacksize-1 do
            qlvm_state.stackNamespace[i] = namespaceHandler:GetNamespace()
        end
    end

    -- constant 값들
    qlvm_state.constantTableNamespace = namespaceHandler:GetNamespace()
    qlvm_state.constantNamespace = {}
    qlvm_state.constantValues = {}
    if proto.k[0] then
        for i=0,#proto.k do
            qlvm_state.constantNamespace[i] = namespaceHandler:GetNamespace()
            local value = proto.k[i]
            local valueType = type(value)
            if valueType == "string" then
                -- 문자열 상수 포맷
                qlvm_state.constantValues[i] = lvmconst.encodeString(value)
            elseif valueType == "table" and value.__LUAVMTYPE__ == "import" then
                -- 임포팅
                local import = {namespaceHandler.env,"[",qlvm_state.constantTableNamespace,".",qlvm_state.constantNamespace[value[1]]}
                for index,constPos in ipairs(value) do
                    if index ~= 1 then
                        table.insert(import,table.concat{
                            "[",qlvm_state.constantTableNamespace,".",qlvm_state.constantNamespace[constPos],"]"
                        })
                    end
                end
                table.insert(import,"]")
                qlvm_state.constantValues[i] = table.concat(import)
            elseif valueType == "table" and value.__LUAVMTYPE__ == "closure" then
                -- 클로저
                qlvm_state.constantValues[i] = "nil"
            end
        end
    end

    -- 실제 돌아가게 할 코드임
    -- do ...constant function IliiI(Ilili,ilili,...) end 방식으로 이루워짐
    -- 업밸류와 네임스페이스를 받음
    -- 상수를 불러옴
    -- 프로토타입을 함수화함
    qlvm_state.gen = {
        "do;", -- do 블럭
        -- constant 테이블
        "local ",qlvm_state.constantTableNamespace,"={};",
        qlvm_state.newline
    }

    -- constant 를 넣음
    if proto.k[0] then
        for i=0,#proto.k do
            if qlvm_state.constantValues[i] then
                table.insert(qlvm_state.gen,table.concat{
                    qlvm_state.constantTableNamespace,".",qlvm_state.constantNamespace[i],
                    "=",qlvm_state.constantValues[i],";",
                    qlvm_state.newline
                })
            -- else print("what",i)
            end
        end
    end

    -- 함수(proto) 넣음
    table.insert(qlvm_state.gen,table.concat{
        "function ",protoID,"(",qlvm_state.envNamespace,",",qlvm_state.upvaluerefNamespace
    })

    -- 파라메터 넣음
    local numparams = proto.numparams -- 인수 갯수
    if numparams > 0 then
        table.insert(qlvm_state.gen,",")
        table.insert(qlvm_state.gen,table.concat(qlvm_state.stackNamespace,",",0,numparams-1))
    end

    -- 가변인자 넣음
    if qlvm_state.is_vararg then
        table.insert(qlvm_state.gen,",...")
    end

    -- 함수 인자목록 닫음
    table.insert(qlvm_state.gen,")")
    table.insert(qlvm_state.gen,qlvm_state.newline)

    -- 값이 (클로저)proto 인 constant 가져옴
    -- TODO
    --? 잠만 생각해보니까 그럴 필요가 있나 어차피 글로벌임

    -- args 아닌 리지스터 생성
    if proto.maxstacksize-(numparams or 0) > 0 then
        table.insert(qlvm_state.gen,table.concat{
            "local ",
            table.concat(qlvm_state.stackNamespace,",",numparams,proto.maxstacksize-1),
            ";",
            qlvm_state.newline,
        })
    end

    -- 코드제네레이팅
    qlvm_state.position = 0 -- 바이트코드 위치
    qlvm_state.run = true
    while qlvm_state.run do
        -- 바이트코드 한바이트 가져오기
        local insn = proto.code[qlvm_state.position]
        if not insn then break end

        -- op 코드 가져오기
        local op = LUAU_INSN_OP(insn)
        local handle = lvmop[op]

        if handle then
            handle(qlvm_state,insn) -- 오피코드 포맷하기
        else
            print("NO OP HANDLER",op)
            qlvm_state.position = qlvm_state.position + 1
        end
    end

    -- 끝내기
    table.insert(qlvm_state.gen,"end;")
    table.insert(qlvm_state.gen,qlvm_state.newline)
    table.insert(qlvm_state.gen,"end;")

    return table.concat(qlvm_state.gen)
end

local function QLVM_makeExecutable(protos,mainid)
    
end

return {
    QLVM_compileProto = QLVM_compileProto;
    QLVM_makeExecutable = QLVM_makeExecutable;
}
