local handler_module = require 'kong.plugins.openapi-doc.handle_api_doc'
local handle_api_doc = handler_module.handle_api_doc

local OpenAPIDocHandler = {}

function OpenAPIDocHandler:access(conf)
  local request = kong.request
  local response = kong.response
  local req_path = request.get_path()


  if request.get_method() == "GET" and req_path == conf.handler_path then
    local res, err = handle_api_doc(conf)
    if res then
      return response.exit(200, res)
    end
    return response.exit(500, err)
  end

end

OpenAPIDocHandler.PRIORITY = 1000
OpenAPIDocHandler.VERSION = '1.0.0'

return OpenAPIDocHandler

-- vim: filetype=lua:expandtab:shiftwidth=2:tabstop=4:softtabstop=2:textwidth=80
