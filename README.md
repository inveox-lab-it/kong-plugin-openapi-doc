# Kong OpenAPI documentations

[![Build Status](https://travis-ci.org/inveox-lab-it/kong-plugin-openapi-doc.svg?branch=master)](https://travis-ci.org/inveox-lab-it/kong-plugin-openapi-doc)


## Synopsis

This plugin merge API documentation from services into single swagger json. 

## Configuration for Kubernetes
Full config for kubernetes kong plugin

```yaml
apiVersion: configuration.konghq.com/v1
config:
  api_meta:
    info:
      contact:
        email: email@tld.com
      title: API Gateway documentation
      version: v1
  apis:
  - prefix: ServiceA 
    rewrite_path:
      regexp: \/api\/
      replace: /
    url: http://service-a/v2/api-docs
  - prefix: ServiceB 
    url: http://service-b/v2/api-docs
  handler_path: /v1/api-docs
kind: KongPlugin
```


