local info_type = {
  type = "record",
  fields = {
      { description = { type = "string"}},
      { version = { type = "string"}},
      { title = { type = "string"}},
      { contact = {
        type = "record",
        fields = {
          { email = { type = "string" }}
        }
      }},
      { license = {
        type = "record",
        fields = {
          { name = { type = "string" }},
          { url = { type = "string"}}
        }}},
      { termsOfService = { type = "string"}}
  }
}

return {
  name = "openapi-doc",
  fields = {
    { config = {
      type = "record",
      fields = {
        { http_config = {
          type = "record",
          fields = {
            { connect_timeout = { default = 1000, type = "number" }},
            { send_timeout = { default = 6000, type = "number" }},
            { read_timeout = { default = 6000, type = "number" }},
            { keepalive_timeout = { default = 60, type = "number" }},
            { keepalive_pool_size = { default = 1000, type = "number" }},
          }
        }},
        { api_meta = {
          type = "record",
          fields = {
            { info = info_type },
            { basePath = { type = "string", default = "/"}},
            { schemes = {
              type = "array",
              default = {"http", "https"},
              elements = {
                type = "string"
              }}
            }
          }}},
        { apis = {
            type = "array",
            required = true,
            elements = {
                type = "record",
                fields = {
                  { url = { type = "string"}},
                  { prefix = { type = "string"}},
                  { rewrite_path = {
                      type = "record",
                      fields = {
                        { regexp = { type = "string"}},
                        { replace = { type = "string"}}
                      }
                    }}
                }}
        }},
        { handler_path = { type = "string", default = "/v2/api-docs"}},
        { ignored_paths = {
          type = "array",
          elements = {
            type = "string"
          }
        }},
        { whitelisted_paths = {
          type = "array",
          elements = {
            type = "string"
          }
        }}
       }}
    }}
  }

