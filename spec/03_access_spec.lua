local helpers = require "spec.helpers"
local cjson = require "cjson"
local server_helper = require 'spec.unit_helpers'
local http_server_with_body = server_helper.http_server_with_body
local read_all = server_helper.read_all

describe("Plugin: openapi-doc access features: whitelist, definitions rewrite", function()
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
          basePath = '/v1',
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
        whitelisted_paths = {
          '/pet.*',
          '^/admin-users$'
        },
        apis = {
          {
            url = 'http://' .. helpers.mock_upstream_host .. ':' .. upstream_port,
            rewrite_path = {
              regexp = "\\/api\\/v1\\/",
              replace = "/"
            },
            prefix = 'api_prefix_'
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
    local expected = cjson.decode(read_all('spec/fixtures/result_whitelist_def_replace.json'))
    assert.same(expected, json)
  end)

  it("should merge swagger doc - array", function()
    upstream = http_server_with_body(upstream_port, 'spec/fixtures/upstream-1-array.json')
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
    local expected = cjson.decode(read_all('spec/fixtures/result_whitelist_def_replace_array.json'))
    assert.same(expected, json)
  end)


end)

-- vim: filetype=lua:expandtab:shiftwidth=2:tabstop=4:softtabstop=2:textwidth=80
