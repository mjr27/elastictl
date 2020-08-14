import strformat, uri, httpclient, json, base64, logging

type
    ElasticHost* = object of RootObj
        host: string
        port: int
        user: string
        password: string

    ElasticClient* = object of RootObj
        host: ElasticHost
        http: HttpClient
        repositoryName: string
        indexName: string

    HttpResponse * = JsonNode 

    ElasticHttpError* = object of CatchableError
        statusCode: HttpCode
        error: string
        body: HttpResponse


proc newHost*(host="localhost", port=9200, user="", password=""):ElasticHost = ElasticHost(host:host, port:port, user: user, password: password)
proc auth(host: ElasticHost) : string =  base64.encode &"{host.user}:{host.password}"
proc hasAuth(host: ElasticHost) : bool = (host.user != "") and (host.password != "")

proc newClient*(host: ElasticHost, repository: string, index: string): ElasticClient = ElasticClient(host: host, http: newHttpClient(), repositoryName: repository, indexName: index)

proc indexUri(client : ElasticClient) : Uri = parseUri( &"http://{client.host.host}:{client.host.port}" )

proc getUri(client: ElasticClient, uri: string) : Uri = client.indexUri() / uri ? {"format": "json"}

proc request(client: ElasticClient, uri: string, httpMethod: HttpMethod, body: string) : HttpResponse {.raises:[ElasticHttpError].} =
    try:
        let 
            absoluteUri = client.getUri(uri)
            headers = newHttpHeaders()
        
        headers.add("Content-Type", "application/json")
        if client.host.hasAuth():
            headers.add("Authorization", &"Basic {client.host.auth()}")

        info("Requesting ", $absoluteUri)
        let response = client.http.request($absoluteUri, $httpMethod, body, headers)

        let code = response.code()
        let body = response.body()

        debug("Response body is ", body)
        if code.is3xx():
            return nil

        if code.is4xx() or code.is5xx():
            raise newException(ElasticHttpError, body)
        
        if body == "":
            return nil
        return (HttpResponse)parseJson(body) 
    except:
        raise newException(ElasticHttpError, getCurrentExceptionMsg(), getCurrentException())
        

proc request(client: ElasticClient, uri: string, httpMethod: HttpMethod) : HttpResponse = request(client, uri, httpMethod, "")

proc makeData(node: JsonNode) : string = $node

proc get(client: ElasticClient, uri: string) : HttpResponse = client.request(uri, HttpMethod.HttpGet)
proc delete(client: ElasticClient, uri: string) : HttpResponse = client.request(uri, HttpMethod.HttpDelete)

proc put(client: ElasticClient, uri: string, data: JsonNode) : HttpResponse = client.request(uri, HttpMethod.HttpPut, makeData(data))
proc put(client: ElasticClient, uri: string) : HttpResponse = client.request(uri, HttpMethod.HttpPut)

proc post(client: ElasticClient, uri: string, data: JsonNode) : HttpResponse = client.request(uri, HttpMethod.HttpPost, makeData(data))
proc post(client: ElasticClient, uri: string) : HttpResponse = client.request(uri, HttpMethod.HttpPost)

proc getIndexList*(client: ElasticClient) : seq[TaintedString] = 
  result = newSeq[string](0)
  let
    response = client.get("_cat/indices")
  if response == nil:
    return
  for indexInfo in response.getElems():
    let indexName: string = indexInfo{"index"}.getStr()
    if indexName != "":
      add(result, indexName)
  return result

proc getSnapshotList*(client: ElasticClient) : seq[TaintedString] = 
  result = newSeq[string](0)
  let
    response = client.get(&"_snapshot/{client.repositoryName}/_all")
  if response == nil:
    return
  for snapshotInfo in response["snapshots"].getElems():
    let snapshotInfo: string = snapshotInfo{"snapshot"}.getStr()
    if snapshotInfo != "":
      add(result, snapshotInfo)
  return result

proc restoreSnapshot* (client: ElasticClient, snapshotName: string) : bool = 
  # post http://localhost:9200/_snapshot/${REPOSITORY}/${SNAPSHOT}/_restore?wait_for_completion=true
  let json = %* {
    "indices": client.indexName,
    "ignore_unavailable": true,
    "include_global_state": false,              
    "rename_pattern": "^.*$",
    "rename_replacement": snapshotName,
    "include_aliases": false
  };
  echo $(client.post(&"_snapshot/{client.repositoryName}/{snapshotName}/_restore", json))
  return true
