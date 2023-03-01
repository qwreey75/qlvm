
--[[
    # Author        : Qwreey / qwreey75@gmail.com / github:qwreey75
    # Create Time   : 2023-02-26 17:15:17
    # Modified by   : Qwreey
    # Modified time : 2023-03-01 17:04:13
    # Description   : |
        Time format = yyy-mm-dd hh:mm:ss
        Time zone = GMT+9
        변수명을 만들기 위해 사용되는 랜덤 아이디 생성기
        겹침을 방지하고 처음 시드로 다시 반복되는 결과를
        산출할 수 있음
 ]]

local baseLength = 12
local concat = table.concat
local insert = table.insert
local random = math.random
local setRandomSeed = math.randomseed
local floor = math.floor
local idStartCharacters = {
    "i","I","l"
}
local idStartCharactersLength = #idStartCharacters
local idCharacters = {
    "i","I","l","1"
}
local idCharactersLength = #idCharacters

local namespaceHandler = {}
namespaceHandler.__index = namespaceHandler

function namespaceHandler.new(startSEED)
    local this = setmetatable({seed = floor(startSEED)%(2^24),checked = {}},namespaceHandler)
    this.strchar = this:GetNamespace()
    this.bit = this:GetNamespace()
    this.bor = this:GetNamespace()
    this.env = this:GetNamespace()
    this.tmp = this:GetNamespace()
    this.createWrapper = this:GetNamespace()
    this.two = this:GetNamespace()
    this.one = this:GetNamespace()
    this.three = this:GetNamespace()
    this.four = this:GetNamespace()
    this.five = this:GetNamespace()
    return this
end

-- 변수 명을 생성함
function namespaceHandler:GetNamespace()
    -- 첫 시드 생성
    local seed = self.seed
    self.seed = seed + baseLength
    setRandomSeed(seed+1)

    -- 반복
    local result = {idStartCharacters[random(1,idStartCharactersLength)]}
    for i = 2,baseLength+1 do
        setRandomSeed(seed+i)
        insert(result,idCharacters[random(1,idCharactersLength)])
    end
    result = concat(result)

    -- 겹침 방지
    if self.checked[result] then return self:GetNamespace() end
    self.checked[result] = true
    return result
end

return namespaceHandler
