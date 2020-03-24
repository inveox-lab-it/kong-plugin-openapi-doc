local helpers = require "spec.helpers"
local cjson = require "cjson"


local function dirname(str)
	if str:match(".-/.-") then
		local name = string.gsub(str, "(.*/)(.*)", "%1")
		return name
	else
		return ''
	end
end

local function readAll(file)
  local file_path = debug.getinfo(1, 'S').source:sub(2)
  local cwd = dirname(file_path)

  local f = io.open(cwd .. '../'.. file, "rb")
  local content = f:read("*all")
  f:close()
  return content
end

local function http_server_with_body(port, file, sc)
  if sc == nil then
    sc = "200 OK"
  end
  local body = readAll(file)
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

describe("Plugin: openapi-doc access", function()
  local proxy_client
  local service_a
  local upstream_port = 16566
  local service_a_port = 16666
  local upstream

  setup(function()
    local bp = helpers.get_db_utils(nil, {
      "routes",
      "services",
      "plugins",
    }, { "openapi-doc" })

    local service = bp.services:insert {
      host = helpers.mock_upstream_host,
      port = helpers.mock_upstream_port,
      protocol = helpers.mock_upstream_protocol,
    }

    bp.routes:insert {
      protocols = { "http" },
      hosts = { "service.test" },
      service = { id = service.id },
    }

    bp.plugins:insert {
      name = "openapi-doc",
      service = { id = service.id },
      config = {
        api_meta = {
          info = {
            contact = {
              email = 'apiteam@swagger.io'
            },
            description = 'api testy',
            license = {
              name = 'Apache 2.0',
              url = 'http://www.apache.org/licenses/LICENSE-2.0.html'
            },
          termsOfService = 'http://swagger.io/terms/',
          title = 'Swagger Petstore',
          version = '1.0.0'
          }
        },
        ignored_paths = {
          '.*ignore-me.*',
          '\\/ignore2-me\\/admin-users'
        },
        apis = {
          {
            url = 'http://' .. helpers.mock_upstream_host .. ':' .. upstream_port,
            rewrite_path = {
              regexp = "\\/api\\/v1\\/",
              replace = "/"
            }
          },
          {
            url = 'http://' .. helpers.mock_upstream_host .. ':' .. service_a_port,
          }
        }
      }
    }

    assert(helpers.start_kong {
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "bundled,openapi-doc",
    })
    proxy_client = helpers.proxy_client()
  end)

  teardown(function()
    if proxy_client then
      proxy_client:close()
    end
    helpers.stop_kong()
  end)

  after_each(function()
    if upstream and upstream:alive() then
      upstream:join()
    end

    if service_a and service_a:alive() then
      service_a:join()
    end

    upstream = nil
    service_a = nil

    collectgarbage()
  end)

  it("should merge swagger doc", function()
    upstream = http_server_with_body(upstream_port, 'spec/fixtures/upstream-1.json')
    service_a = http_server_with_body(service_a_port, 'spec/fixtures/upstream-2.json')
    helpers.wait_until(function()
      return service_a:alive() and upstream:alive()
    end, 1)

    local res = proxy_client:get("/v2/api-docs", {
      headers = {
        host = "service.test",
        ["Content-Type"] = "application/json",
      },
    })
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    local expected = cjson.decode(readAll('spec/fixtures/result.json'))
    assert.same(expected, json)
  end)

end)

-- vim: filetype=lua:expandtab:shiftwidth=2:tabstop=4:softtabstop=2:textwidth=80
