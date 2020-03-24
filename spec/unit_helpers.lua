local _M = {}

local function dirname(str)
	if str:match(".-/.-") then
		local name = string.gsub(str, "(.*/)(.*)", "%1")
		return name
	else
		return ''
	end
end

local function read_all(file)
  local file_path = debug.getinfo(1, 'S').source:sub(2)
  local cwd = dirname(file_path)

  local f = io.open(cwd .. '../'.. file, "rb")
  local content = f:read("*all")
  f:close()
  return content
end
_M.read_all = read_all

local function http_server_with_body(port, file, sc)
  if sc == nil then
    sc = "200 OK"
  end
  local body = read_all(file)
  local threads = require "llthreads2.ex"
  local thread = threads.new({
    function(port, body, sc)
      local socket = require "socket"
      local server = assert(socket.tcp())
      assert(server:setoption('reuseaddr', true))
      local status = server:bind("*", port)
      while not status do
        status = server:bind("*", port)
      end
      assert(server:listen())
      server:settimeout(3)
      local client, err = server:accept()
      if err ~= nil then
        return
      end
      client:settimeout(3)

      local line
      line, err = client:receive()
      if err then
        print('error on read', err)
      end
      while line and line ~= ''  do
        line, err = client:receive()
        if err then
          break
        end
      end
      client:send("HTTP/1.1 ".. sc .."\r\nConnection: close\r\nContent-Type: application/json\r\nContent-Length: " .. #body.. "\r\n\r\n"..body)
      client:close()
      server:close()
    end
  }, port, body, sc)

  return thread:start(false, false)
end
_M.http_server_with_body = http_server_with_body

local function write_file(path, text)
  local file_path = debug.getinfo(1, 'S').source:sub(2)
  local cwd = dirname(file_path)
  print('Writing file ', cwd .. path)
  local file = io.open(cwd .. path, 'a')
  file:write(text)
  file:close()
end
_M.write_file = write_file

return _M