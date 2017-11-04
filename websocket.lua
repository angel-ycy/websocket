--[[
    MIT License

    Copyright (c) 2017 Marvin Countryman

    Permission is hereby granted, free of charge, to any person 
    obtaining a copy of this software and associated 
    documentation files (the "Software"), to deal in the 
    Software without restriction, including without limitation 
    the rights to use, copy, modify, merge, publish, distribute,
    sublicense, and/or sell copies of the Software, and to 
    permit persons to whom the Software is furnished to do so, 
    subject to the following conditions:

    The above copyright notice and this permission notice shall 
    be included in all copies or substantial portions of the 
    Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY 
    KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE 
    WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR 
    PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS 
    OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR 
    OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR 
    OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE 
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

    RFC6455 - https://tools.ietf.org/html/rfc6455
]]
if not bromsock then require "bromsock" end

websocket = {}
websocket.version = 100
websocket.loglevel = 4  -- higher = more verbose

websocket.protocolVersion = "13"
websocket.httpHeaderMax = 64

-- Opcodes
websocket.OP_CNT    = 0x00
websocket.OP_TEXT   = 0x01
websocket.OP_BINARY = 0x02
                   -- 0x03-0x07 - non-control
websocket.OP_CLOSE  = 0x08
websocket.OP_PING   = 0x09
websocket.OP_PONG   = 0x0A
                   -- 0x0B-0x0F - control

-- States
websocket.OPEN    = 0x01
websocket.CLOSED  = 0x02
websocket.OPENING = 0x03
websocket.CLOSING = 0x04

-- Log levels
websocket.ERROR   = 1
websocket.WARN    = 2
websocket.INFO    = 3
websocket.VERBOSE = 4

local function log(level, fmt, ...)
    if websocket.loglevel < level then 
        return 
    end 

    print("[websocket] "..string.format(fmt, ...))
end
local function parseUri(uri)
    -- ws = "ws:" "//" host [ ":" port ] path [ "?" query ]
    -- wss = "wss:" "//" host [ ":" port ] path [ "?" query ]
    local i = 1
    local s, e
    local protocol, host, port, path, query

    -- Parse protocol
    s, e = string.find(uri, "^[a-zA-Z]+://", i)
    if s then 
        i = e + 1
        protocol = string.lower(string.sub(uri, s, e - 3))

        if protocol ~= "wss" and  
            protocol ~= "ws" then 

            error("Invalid protocol '"..protocol.."' in uri '"..uri.."'")
        end 
    else
        error("Undefined protocol in uri '"..uri.."'")
    end 

    -- Parse host
    s, e = string.find(uri, "^[^:/\\]+", i)
    if s then 
        i = e + 1
        host = string.sub(uri, s, e)
    else 
        error("Undefined host in uri '"..uri.."'")
    end 

    -- Parse port
    s, e = string.find(uri, "^:[0-9]+", i)
    if s then 
        i = e + 1
        port = string.sub(uri, s + 1, e)
    else 
        -- Default ports
        if protocol == "wss" then port = 443 end 
        if protocol == "ws" then port = 80 end 
    end 

    -- Parse path
    s, e = string.find(uri, "^[^%?]+", i)
    if s then 
        i = e + 1
        path = string.sub(uri, s, e)
    end 

    -- Parse query
    s, e = string.find(uri, "^%?.+$", i)
    if s then 
        i = e 
        query = string.sub(uri, s, e)
    end 

    return {
        protocol = protocol,
        host = host,
        port = port,
        path = path,
        query = query
    }
end
local function randomKey()
    return util.Base64Encode("16b")
end

local Frame do 
    Frame = {}
    Frame.__index = Frame

    function Frame.new(fin, rsv1, opcode, mask, payload) 
    end
end 

local Client do 
    Client = {}
    Client.__index = Client 

    function Client.new(uri)
        local sock = BromSock()
        local client
        
        client = setmetatable({
            _listeners = {},

            uri = parseUri(uri),
            state = websocket.CLOSED
        }, Client)
        
        sock:SetCallbackSend(function(_, ...)
            print(_, ...)
        end)
        sock:SetCallbackReceive(function(_, packet, ...)
            print(_, packet, ...)
            if client.state == websocket.OPENING then
                local headers = {}
                local request = packet:ReadLine()
                local count = 0
                local line 

                log(websocket.VERBOSE, "Handshake: "..request)
                
                -- Parse HTTP headers
                while true do 
                    -- Too many headers
                    if count > websocket.httpHeaderMax then 
                        error("HTTP header count exceeded "..
                              "maximum allowed count of "..
                              websocket.httpHeaderMax
                        )
                    end 

                    line = packet:ReadLine()
                    log(websocket.VERBOSE, "Handshake: "..line)

                    -- Check valid line (if null, probably eos)
                    if not line then break end 
                    if line == "" then break end 

                    -- Header key/value
                    local name = string.find("^[^:]+", line)
                    local value = string.find("[:][ ]*.+$", line)

                    headers[string.lower(name)] = value
                    count = count + 1
                end 

                if request ~= "HTTP/1.1 101 Switching Protocols" then
                    return client:_fail("Invalid response from server")
                end 
                if string.lower(headers["connection"]) ~= "upgrade" then 
                    return client:_fail("Invalid connection header")
                end
                if string.lower(headers["upgrade"]) ~= "websocket" then 
                    return client:_fail("Invalid upgrade header")
                end 
                if string.lower(headers["sec-websocket-key"]) ~= "" then
                    return client:_fail("Invalid key header")
                end 

                client.state = websocket.OPEN
            elseif client.state == websocket.OPEN then 
                self.frame = self.frame or Frame.new(self)
                self.frame:read(packet)

                if self.frame.state == Frame.DONE then 
                    self:_onFrame(self.frame)
                    self.frame = Frame.new(self)
                end
            end 
        end)
        sock:SetCallbackConnect(function(_, success, ...) 
            print(success, ...)
            if not success then error "Failure" end

            client.state = websocket.OPENING

            local _ = string.format
            local packet = BromPacket()
            local socketKey = randomKey()
            local socketVersion = websocket.protocolVersion

            -- Send handshake
            packet:WriteLine(_("GET %s HTTP/1.1", client.uri.path))
            packet:WriteLine(_("Host: %s", client.uri.host))
            packet:WriteLine(_("Sec-WebSocket-Key: %s", socketKey))
            packet:WriteLine(_("Sec-WebSocket-Version: %s", socketVersion))
            packet:WriteLine("Connection: Upgrade")
            packet:WriteLine("Upgrade: websocket")
            packet:WriteLine("")

            log(websocket.VERBOSE, "Sending Handshake")
            sock:Send(packet, true)
            log(websocket.VERBOSE, "Awaiting Handshake")
            sock:ReceiveUntil "\r\n\r\n"
        end)
        sock:SetCallbackDisconnect(function(...) 
            print(...)
        end)
        sock:Connect(client.uri.host, client.uri.port)
        sock:SetTimeout(1000)

        if client.uri.protocol == "wss" then
            sock:StartSSLClient()
        end

        log(websocket.VERBOSE, "Connecting: host="..client.uri.host)
        log(websocket.VERBOSE, "Connecting: port="..client.uri.port)

        client.sock = sock

        return client
    end

    --
    function Client:_fail(message)
        -- Disconnect
        self:_emit("error", message)
    end 
    --
    function Client:_emit(event, data)
        if type(self._listeners[event]) == "function" then 
            self._listeners[event](data)
        end
    end
    --
    function Client:_onFrame(frame)
        if frame.opcode == websocket.OP_CLOSE then 
        elseif frame.opcode == websocket.OP_PING then 
            self:_sendFrame(true, websocket.OP_PONG, frame.payload)
        elseif frame.opcode == websocket.OP_PONG then 
        elseif frame.opcode == websocket.OP_TEXT then 
        elseif frame.opcode == websocket.OP_BINARY then 
        elseif frame.opcode == websocket.OP_CNT then 
        end
    end
    --
    function Client:_sendFrame(fin, opcode, data) end 

    --[[
        Creates/registers new event receiver.

        @param {string} event Name of event
        @param {function} callback Function to be called
    ]]
    function Client:on(event, callback) 
        self._listeners[event] = callback 
    end 

    --[[
        Removes existing event receiver.

        @param {string} event Name of event
    ]]
    function Client:off(event)
        self._listeners[event] = nil
    end

    --[[
        Sends data to server.

        @param {object} data Data to send
    ]]
    function Client:send(data)
        if self.state ~= websocket.OPEN then 
            error("Websocket not opened")
        end
    end

    --[[
        
    ]]
    function Client:close(code, reason)
        if self.state == websocket.CLOSED then return end 
        if self.state == websocket.OPENING then 
            -- TODO: This
            self._emit("error", "Closed before the connection is established")
            return 
        end 

        self.state = websocket.CLOSING
        -- TODO: Send close frame
    end
end

--[[

]]
function websocket.connect(uri) 
    return Client.new(uri)
end