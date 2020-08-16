import asyncdispatch
import base64
import httpclient
import json
import logging
import strformat
import uri

type
    JsonHttpHost* = object of RootObj
        root*: Uri
        user*: string
        password*: string
    JsonHttpResponse* = JsonNode
    JsonHttpError* = object of IOError


proc auth(host: JsonHttpHost): string =
    base64.encode &"{host.user}:{host.password}"
proc hasAuth(host: JsonHttpHost): bool =
    (host.user != "") and (host.password != "")
proc getUri(host: JsonHttpHost, uri: string): Uri =
    host.root / uri
proc makeData(node: JsonNode): string =
    $node


proc request(host: JsonHttpHost, uri: string, httpMethod: HttpMethod,
        body: string): Future[JsonHttpResponse] {.async.} =
    try:
        let
            absoluteUri = host.getUri(uri)
            headers = newHttpHeaders({"Accept": "application/json"})
            http = newAsyncHttpClient()
        if host.hasAuth():
            headers.add("Authorization", &"Basic {host.auth()}")
        info("Requesting ", $absoluteUri)

        let response: AsyncResponse = await http.request($absoluteUri,
                $httpMethod, body, headers)

        let code = response.code()
        let body = await response.body()

        debug("Response body is ", body)
        if code.is3xx():
            return nil

        if code.is4xx() or code.is5xx():
            raise newException(JsonHttpError, body)

        if body == "":
            return nil
        return (JsonHttpResponse)parseJson(body)
    except:
        debug body
        raise newException(JsonHttpError, getCurrentExceptionMsg(),
                getCurrentException())

proc request(host: JsonHttpHost, uri: string, httpMethod: HttpMethod): Future[
        JsonHttpResponse] = request(host, uri, httpMethod, "")

proc newJsonHost*(host: Uri, user = "", password = ""): JsonHttpHost = JsonHttpHost(
        root: host, user: user, password: password)
proc get*(host: JsonHttpHost, uri: string): Future[
        JsonHttpResponse] = host.request(uri, HttpMethod.HttpGet)
proc delete*(host: JsonHttpHost, uri: string): Future[
        JsonHttpResponse] = host.request(uri, HttpMethod.HttpDelete)

proc put*(host: JsonHttpHost, uri: string, data: JsonNode): Future[
        JsonHttpResponse] = host.request(uri, HttpMethod.HttpPut, makeData(data))
proc put*(host: JsonHttpHost, uri: string): Future[
        JsonHttpResponse] = host.request(uri, HttpMethod.HttpPut)

proc post*(host: JsonHttpHost, uri: string, data: JsonNode): Future[
        JsonHttpResponse] = host.request(uri, HttpMethod.HttpPost, makeData(data))
proc post*(host: JsonHttpHost, uri: string): Future[
        JsonHttpResponse] = host.request(uri, HttpMethod.HttpPost)

