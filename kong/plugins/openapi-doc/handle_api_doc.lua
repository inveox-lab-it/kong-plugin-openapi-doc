local http = require 'resty.http'
local insert = table.insert
local cjson = require('cjson.safe').new()
local utils = require('kong.tools.utils')
local common_plugin_status, common_plugin_headers = pcall(require, 'kong.plugins.common.headers')

local sub = ngx.re.sub
local gsub = ngx.re.gsub
local match = ngx.re.match
local table_contains = utils.table_contains
local table_concat = utils.concat
cjson.decode_array_with_array_mt(true)

local API_KEYS = {'securityDefinitions'}

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

local function process_tags(doc, api, tags, to_remove)
  if tags then
    for i = 1, #tags do
      if table_contains(to_remove, tags[i].name) == false then
        if api.prefix then
          tags[i].name = api.prefix .. tags[i].name
        end
        insert(doc.tags, tags[i])
      end
    end
  end
end

local function add_prefix_path_object(value, api_prefix)
  for _, data in pairs(value) do
    if data.operationId then
      data.operationId = api_prefix .. data.operationId
    end

    if data.tags then
      for i = 1, #data.tags do
        data.tags[i] = api_prefix .. data.tags[i]
      end
    end
  end
  return value
end

local function propagate_path_remove(path, dest)
  for _, data in pairs(path) do
    if data.tags then
      for _, tag in ipairs(data.tags) do
        insert(dest, tag)
      end
    end
  end
end

local function get_tags_from_path(path)
  local dest = {}
  for _, data in pairs(path) do
    if data.tags then
      for _, tag in ipairs(data.tags) do
        insert(dest, tag)
      end
    end
  end
  return dest
end

local function process_paths(conf, api, doc, paths)
  local tags_to_remove = {}
  local tags_to_leave = {}
  if paths then
    local api_prefix = api.prefix
    for name, value in pairs(paths) do
        if should_add_path(conf, name)  then
          if api.rewrite_path then
            name = rewrite_path(api.rewrite_path, name)
          end
          if api_prefix then
            value = add_prefix_path_object(value, api_prefix)
          end
          doc.paths[name] = value
          tags_to_leave = table_concat(tags_to_leave, get_tags_from_path(value))
        else
          propagate_path_remove(value, tags_to_remove)
        end
    end
  end

  -- if tag occure more then 1 time and it used by path that is not removed
  -- it should not be removed as well
  for i = 1, #tags_to_remove do
    if table_contains(tags_to_leave, tags_to_remove[i]) then
      tags_to_remove[i] = nil
    end
  end
  return tags_to_remove
end

local function  add_prefix_to_definitions(body, api)
  local new_body, _, err  = gsub(body, [[(#/definitions/)]], '$1' .. api.prefix, 'io')
  if err then
    kong.log.err('Unable to replace definitions', err, ' for ', api.prefix)
    return nil, err
  end
  new_body, _, err  = gsub(new_body, [[«([a-zA-Z0-9]+)»]], '«' .. api.prefix .. '$1»' , 'io')
  if err then
    kong.log.err('Unable to replace definitions', err, ' for ', api.prefix)
    return nil, err
  end
  return new_body, nil
end

local function  replace_body(body, api)
  local new_body = body
  local err = nil
  for _, v in ipairs(api.body_transform) do
    new_body, _, err  = gsub(new_body, v.regexp, v.replace, 'jo')
    if err then
      kong.log.err('Unable to replace body ', err, ' for ', v.regexp, ' ', v.replace)
      return nil, err
    end
  end
  return new_body, err
end

local function process_definitions(api, doc, definitions )
  if definitions then
    for name, value in pairs(definitions) do
        if api.prefix then
          name = api.prefix .. name
          if value.title then
            value.title = api.prefix .. value.title
          end
        end
        doc.definitions[name] = value
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
    local req_headers = nil
    if common_plugin_status then
      req_headers = common_plugin_headers.get_upstream_headers(kong.request)
    end
    local res, err = client:request_uri(api.url, {
      method = 'GET',
      headers = req_headers,
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

    local prepared_body = res.body
    if api.prefix then
      local new_body, err = add_prefix_to_definitions(prepared_body, api)
      if err then
        return nil, err
      end
      prepared_body = new_body
    end

    local api_res = cjson.decode(prepared_body)
    if not api_res then
      return nil, 'unable to parse json from ' .. api.url
    end

    local to_remove = process_paths(conf, api, doc, api_res.paths)
    process_tags(doc, api, api_res.tags, to_remove)
    process_definitions(api, doc, api_res.definitions)
    process_rest(doc, api_res)
    if api.body_transform then
      local api_doc_body = cjson.encode(doc)
      local new_body, err = replace_body(api_doc_body, api)
      if err then
        return nil, err
      end
      doc = cjson.decode(new_body)
      if not doc then
        return nil, 'unable to decode body after body_transform'
      end
    end
  end
  return doc, nil
end

return {
  handle_api_doc = handle_api_doc
}
