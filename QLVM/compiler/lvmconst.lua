
--[[
    # Author        : Qwreey / qwreey75@gmail.com / github:qwreey75
    # Create Time   : 2023-02-27 03:17:22
    # Modified by   : Qwreey
    # Modified time : 2023-03-01 18:17:25
    # Description   : |
        Time format = yyy-mm-dd hh:mm:ss
        Time zone = GMT+9
        문자열 난독화, 클로저 워래퍼
 ]]

local project = require("QLVM/project")

-- add number, bit, wrapperCreator
local function header(namespace)
    local wrapperEnv = namespace:GetNamespace()
    local wrapperRef = namespace:GetNamespace()
    local wrapperFnc = namespace:GetNamespace()
    return table.concat{
        "local ",namespace.strchar,",",namespace.tmp,",",namespace.env,",",namespace.bit,",",namespace.two,",",namespace.one,",",namespace.four,",",namespace.five,
        [[=('')["\99\104\97\114"],nil,getfenv(),nil,nil,nil,nil,nil;]],
        namespace.tmp,"=",namespace.strchar,"(0b111^0b10*0x2,0x69,0b10^0x2*0x1D);",
        namespace.bit,"=",namespace.env,"[",namespace.tmp,"..",namespace.strchar,"(0x28+0xB,0x32)]or(",namespace.env,"[",namespace.tmp,"]);",
        namespace.tmp,"=",namespace.strchar,"(0b10*(0b10*0b10+0b11)^0x2,0x6F,0b11*0b10*0x13);",
        namespace.bor,"=",namespace.bit,"[",namespace.tmp,"];",
        namespace.two,"=",
        namespace.bor,"(0b1,1",
        [[,0b1,0x0,0x1,0b0,0x0,0b1,0x1,0b0,0x1,0x0,0x0,]],
        [[0x0,0b1,0x1,0x1,0x0,0x1,0b0,0x1,0x1,0x1,0b00,]],
        [[0x1,0b1,0x1,0x0)+]],
        namespace.bor,[[(0b1,0x1,0x1,0x1,0b0,0x0,1,]],
        [[0x1,0x1,0b1,0x1,0x1,0b1,0x0,0x0,0b0,0x1,0,00,]],
        [[0b1,0x1,0x0,0x0,0b1,0x0,0x1,0b0,0x0,0x1,0b1);]],
        "function ",namespace.createWrapper,"(",wrapperEnv,",",wrapperRef,",",wrapperFnc,")return(function(...)",wrapperFnc,"(",wrapperEnv,",",wrapperRef,",...)end)end;",
        namespace.one,"=",namespace.two,"/",namespace.two,";",
        namespace.three,"=",namespace.two,"+",namespace.one,";",
        namespace.four,"=",namespace.two,"^",namespace.two,";",
        namespace.five,"=",namespace.four,"+",namespace.one,";",
    }
end

local function factorization()

end

-- TODO: encode strings
local function encodeString(value)
    -- if project.debug then
        return table.concat{
            "'",value:gsub("\\","\\\\"):gsub("\n","\\n"):gsub("\'","\\\'"),"'"
        }
    -- end
end

-- TODO: encode numbers
-- local function encodeNumber(string)
-- end

return {
    header = header,
    encodeString = encodeString,
    -- encodeNumber = encodeNumber
}
