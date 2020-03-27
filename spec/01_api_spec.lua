local helpers = require 'spec.helpers'

describe('Plugin: openapi-doc API', function()
  local admin_client
  setup(function()
    helpers.get_db_utils()
    assert(helpers.start_kong({
      plugins = "bundled, openapi-doc",
    }))

    admin_client = helpers.admin_client()
  end)
  teardown(function()
    if admin_client then
      admin_client:close()
    end

    helpers.stop_kong()
  end)

  it('plugin can\'t be configured with wrong spec', function()
    local res = assert(admin_client:send {
      method = 'POST',
      path = '/plugins',
      body = {
        name = 'openapi-doc'
      },
      headers = {
        ['content-type'] = 'application/json'
      }
    })
    assert.res_status(400, res)
  end)

  it('plugin can be configured full config', function()
    local res = assert(admin_client:send {
      method = 'POST',
      path = '/plugins',
      body = {
        name = 'openapi-doc',
        config = {
          api_meta = {
            info = {
              description = 'test',
              version = 'v1',
              title = 'API test',
            },
            basePath = '/'
          },
          apis = {
            {
              url = 'https://api.tld/v2/api-doc'
            }
          }
        }
      },
      headers = {
        ['content-type'] = 'application/json'
      }
    })
    assert.res_status(201, res)
  end)

end)