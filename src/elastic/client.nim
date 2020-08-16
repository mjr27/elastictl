import asyncdispatch
import json
import strformat
import strutils
import tables
import times
import uri
import ./json_http

type
    ElasticClient* = object of RootObj
        host: JsonHttpHost

    ElasticIndexState* = enum
        Green
        Yellow
        Red

    ElasticSnapshotState* = enum
        Success
        InProgress
        Partial
        Error

    ElasticIndex* = object of RootObj
        name*: string
        health*: ElasticIndexState
        date*: Time
        size*: int64
        aliases*: seq[string]

    ElasticRepository* = object of RootObj
        name*: string
        storage*: string

    ElasticSnapshot* = object of RootObj
        name*: string
        state*: ElasticSnapshotState
        date*: Time
        indices*: seq[string]

proc toIndexState(s: string): ElasticIndexState =
    case s.toLower
    of "green": return ElasticIndexState.Green
    of "yellow": return ElasticIndexState.Yellow
    else: return ElasticIndexState.Red

proc toSnapshotState(s: string): ElasticSnapshotState =
    case s.toUpperAscii
    of "SUCCESS": return ElasticSnapshotState.Success
    of "IN_PROGRESS": return ElasticSnapshotState.InProgress
    of "PARTIAL": return ElasticSnapshotState.Partial
    else: return ElasticSnapshotState.Error


proc newClient*(host: JsonHttpHost): ElasticClient = ElasticClient(host: host)

proc parseIndexInfo(index: JsonNode): ElasticIndex =
    result.name = index{"index"}.getStr()
    result.health = toIndexState index{"health"}.getStr()
    result.date = (parseFloat(index["creation.date"].getStr()) /
            1000).fromUnixFloat()
    result.size = parseBiggestInt index["pri.store.size"].getStr()

proc parseSnapshotInfo(snapshot: JsonNode): ElasticSnapshot =
    result.name = snapshot{"snapshot"}.getStr()
    result.state = toSnapshotState snapshot{"state"}.getStr()
    result.date = (snapshot["start_time_in_millis"].getFloat() /
            1000).fromUnixFloat()
    result.indices = snapshot["indices"].to(seq[string])

proc getAliases(client: ElasticClient):
        Future[Table[string, seq[string]]] {.async.} =
    let aliasResponse = await client.host.get("_cat/aliases?h=alias,index")
    for r in aliasResponse.getElems():
        let
            indexName = r{"index"}.getStr()
            aliasName = r{"alias"}.getStr()
        if not result.contains(indexName):
            result[indexName] = newSeq[string]()
        result[indexName].add(aliasName)

proc getIndexList*(client: ElasticClient): Future[seq[ElasticIndex]] {.async.} =
    var returnValue = newSeq[ElasticIndex](0)
    let
        response = await client.host.get(
            "_cat/indices?bytes=b&h=index,health,pri.store.size,creation.date")
        indexAliases = await client.getAliases()

    if response == nil:
        raise newException(JsonHttpError, "Unable to retrieve index list")

    for indexInfo in response.getElems():
        var index = parseIndexInfo indexInfo
        index.aliases = indexAliases.getOrDefault(index.name, @[])
        if index.name != "":
            add(returnValue, index)
    return returnValue


proc getRepositoryList*(client: ElasticClient): Future[seq[
        ElasticRepository]] {.async.} =
    var returnValue = newSeq[ElasticRepository](0)
    let
        response = await client.host.get("_snapshot")
    if response == nil:
        return
    for k, v in response.getFields().pairs:
        var repo: ElasticRepository
        repo.name = k
        repo.storage = v{"type"}.getStr()
        returnValue.add(repo)
    return returnValue

proc getSnapshotList*(client: ElasticClient, repository: string): Future[seq[
        ElasticSnapshot]] {.async.} =
    result = newSeq[ElasticSnapshot](0)
    let
        response = await client.host.get(&"_snapshot/{repository}/_all")
    if response == nil:
        return
    for snapshotInfo in response["snapshots"].getElems():
        let snapshotInfo = parseSnapshotInfo snapshotInfo
        if snapshotInfo.name != "":
            add(result, snapshotInfo)
    return result


proc restoreSnapshot*(client: ElasticClient, repository: string,
        snapshotName: string, indexName: string): Future[bool] {.async.} =
    # post http://localhost:9200/_snapshot/${REPOSITORY}/${SNAPSHOT}/_restore?wait_for_completion=true
    discard client.host.delete(snapshotName)

    let json = %* {
        "indices": indexName,
        "ignore_unavailable": true,
        "include_global_state": false,
        "rename_pattern": "^.*$",
        "rename_replacement": snapshotName,
        "include_aliases": false
    };
    echo $(await client.host.post(&"_snapshot/{repository}/{snapshotName}/_restore", json))
    return true

proc removeAlias(client: ElasticClient, index: string, alias: string): Future[
        void] {.async.} =
    discard await client.host.delete(&"/{index}/_alias/{alias}")

proc removeAlias*(client: ElasticClient, name: string): Future[bool] {.async.} =
    let aliases = await client.getAliases();
    for k, v in aliases:
        if v.contains(name):
            await client.removeAlias(index = k, alias = name)
            return true
    return false


proc removeIndex*(client: ElasticClient, name: string): Future[bool] {.async.} =
    discard await client.host.delete(&"/{name}")
    return true

proc removeSnapshot*(client: ElasticClient, repository: string, snapshot: string): Future[bool] {.async.} =
    let
        encodedRepo = encodeUrl repository
        encodedName = encodeUrl snapshot
    discard await client.host.delete(&"/_snapshot/{encodedRepo}/{encodedName}")
    return true
