local http = require 'resty.http'
local insert = table.insert
local cjson = require('cjson.safe').new()

local sub = ngx.re.sub
local match = ngx.re.match
cjson.decode_array_with_array_mt(true)

local API_KEYS = {'definitions', 'securityDefinitions'}

local function rewrite_path(api_conf, name)
  if api_conf.regexp then
    return sub(name, api_conf.regexp, api_conf.replace, 'io')
  end

  return name
end

local function contains_regexp(list, path)
  for i = 1, #list do
    if match(path, list[i], 'io') then
      return true
    end
  end

  return false
end

local function should_add_path(conf, path)
  if conf.whitelisted_paths and #conf.whitelisted_paths ~= 0 then
    return contains_regexp(conf.whitelisted_paths, path)
  elseif conf.ignored_paths and  #conf.ignored_paths ~= 0 then
    return not contains_regexp(conf.ignored_paths, path)
  end

  return true
end

local function process_tags(doc, tags)
  if tags then
    for i = 1, #tags do
      insert(doc.tags, tags[i])
    end
  end
end

local function process_paths(conf, api, doc, paths)
  if paths then
    for name, value in pairs(paths) do
        if should_add_path(conf, name)  then
          if api.rewrite_path then
            name = rewrite_path(api.rewrite_path, name)
          end
          doc.paths[name] = value
        end
    end
  end
end

local function process_rest(doc, api_res)
  for i = 1, #API_KEYS do
    local key = API_KEYS[i]
    if not doc[key] then
      doc[key] = {}
    end
    if api_res[key] then
      local key_value = api_res[key]
      for name, value in pairs(key_value) do
          doc[key][name] = value
      end
    end
  end
end

local function handle_api_doc(conf)
  local request = kong.request
  local http_config = conf.http_config
  local api_meta = conf.api_meta
  local doc = {
    swagger = '2.0',
    info = api_meta.info,
    host = request.get_host(),
    basePath = api_meta.basePath,
    tags = {},
    paths = {},
    definitions = {},
    schemes = api_meta.schemes,
    securityDefinitions = {}
  }
  local apis = conf.apis
  local client = http.new()

  for i = 1, #apis do
    local api = apis[i]
    client:set_timeouts(http_config.connect_timeout, http_config.send_timeout, http_config.read_timeout)
    local res, err = client:request_uri(api.url, {
      method = 'GET',
    })
    client:set_keepalive(http_config.keepalive_timeout, http_config.keepalive_pool_size)

    if not res then
      kong.log.err('Invalid response from upstream ', api.url, ' ', err )
      return nil, err
    end

    if res.status ~= 200 then
      kong.log.err('Invalid response from upstream ', api.url, ' ', res.status)
      return nil, 'invalid response from ' .. api.url .. ' status ' .. res.status
    end

    local api_res = cjson.decode(res.body)
    if not api_res then
      return nil, 'unable to parse json from ' .. api.url
    end

    process_tags(doc, api_res.tags)
    process_paths(conf, api, doc, api_res.paths)
    process_rest(doc, api_res)
  end
  return doc, nil
end

return {
  handle_api_doc = handle_api_doc
}