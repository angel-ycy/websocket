Msg "================================================================\n":rep(2)
Msg "|||	 'websocket.test.lua' IS FOR TESTING PURPOSES ONLY!!! |||\n":rep(5)
Msg "================================================================\n":rep(2)

if not websocket then include "websocket" end
game.ConsoleCommand "sv_hibernate_think 1\n"

local function describe(info, cb) end 
local function it(info, cb) end
