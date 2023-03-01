local fs = require("fs")
local file = fs.readFileSync("test.out")
local list = {"return {table.concat{\nstring.char("}
local count = 0
for char in file:gmatch"." do
    count = count + 1
    if count%200 == 0 then
        table.remove(list)
        table.insert(list,"),\nstring.char(")
    end
    table.insert(list,char:byte())
    table.insert(list,",")
end
table.remove(list)
table.insert(list,")}}")
fs.writeFileSync("teststrings.lua",table.concat(list))
