
--[[
    # Author        : Qwreey / qwreey75@gmail.com / github:qwreey75
    # Create Time   : 2023-02-25 22:20:26
    # Modified by   : Qwreey
    # Modified time : 2023-03-01 18:24:08
    # Description   : |
        Time format = yyy-mm-dd hh:mm:ss
        Time zone = GMT+9
        컴파일러 메인
 ]]

local lvmload = require("QLVM/compiler/lvmload")
local lvmnamespace = require("QLVM/compiler/lvmnamespace")
local lvmcompile = require("QLVM/compiler/lvmcompile")
local inspact = require("QLVM/inspact")
local lvmconst = require("QLVM/compiler/lvmconst")
local project = require("QLVM/project")

-- 해더를 추가하고 string 로더를 추가함
local function addHeading(mainid,namespace,code,userheader)
    local longTabs = string.rep("\t",512)
    userheader = userheader or "This code have no detail infotmation"
    if project.debug then
        return table.concat{
            "-- THIS CODE WAS COMPILED BY QLVM\n",
            "\n-- string loader\n",
            lvmconst.header(namespace),
            "\n\n-- main code\n",
            code,
            "\n\n-- caller\n",
            mainid,"(",namespace.env,",{})\n"
        }
    end
    return table.concat{
        "--[[\n\n",
        "\tTHIS CODE WAS COMPILED BY QLVM",longTabs,"]]",lvmconst.header(namespace),code,mainid,"(",namespace.env,",{})--[[\n",
        "\tQLVM VERSION ",project.version," BUILD ",project.build,"\n",
        "\tCompiled time : ",os.date(),"\n\n",
        "\t",userheader:gsub("\n","\n\t"):gsub("]]",""),
        "\n\n]]\n"
    }
end

local function obfuscate(bytecode,userheader)
    local protos,mainid = lvmload.luau_load(bytecode)
    local namespaceHandler = lvmnamespace.new(os.time())
    local protoIds = {}
    if protos[0] then
        for i=0,#protos do
            protoIds[i] = namespaceHandler:GetNamespace()
        end
    end

    -- if project.debug then
    --     print(inspact(protos))
    -- end

    local codes = {}
    if protos[0] then
        for i=0,#protos do
            table.insert(codes,lvmcompile.QLVM_compileProto(
                protos[i],protos,protoIds[i],protoIds,namespaceHandler
            ))
        end
    end

    return addHeading(protoIds[mainid],namespaceHandler,table.concat(codes),userheader)
end

local data = require("./teststrings")[1]
-- print(obfuscate(data))
require("fs").writeFileSync("testout.lua",obfuscate(data,require"fs".readFileSync("license")))

return {
    luau_load = lvmload.luau_load
}
