import asyncdispatch
import json
import httpcore
import sequtils
import strformat
import strutils
import sugar
import tables
import times
import uri

import ./json_http

type
    ElasticClient* = object of RootObj
        host: JsonHttpHost
        wait: bool

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

proc first[T](data: seq[T], filter: proc (row: T): bool): (T, bool) = 
    for item in data:
        if filter(item): return (item, true)
    result = (default(T), false)

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


proc newClient*(host: JsonHttpHost, wait: bool): ElasticClient = ElasticClient(host: host, wait: wait)

proc parseIndexInfo(index: JsonNode): ElasticIndex =
    result.name = index{"index"}.getStr()
    result.health = toIndexState index{"health"}.getStr()
    result.date = (parseFloat(index["creation.date"].getStr()) / 1000).fromUnixFloat()
    result.size = 
        if index["pri.store.size"].kind == JString: parseBiggestInt index["pri.store.size"].getStr()
        else: BiggestInt(-1)

proc parseSnapshotInfo(snapshot: JsonNode): ElasticSnapshot =
    result.name = snapshot{"snapshot"}.getStr()
    result.state = toSnapshotState snapshot{"state"}.getStr()
    result.date = (snapshot["start_time_in_millis"].getFloat() /
            1000).fromUnixFloat()
    result.indices = snapshot["indices"].to(seq[string])

proc getAliases(client: ElasticClient): Future[TableRef[string, seq[string]]] {.async.} =
    result = newTable[string, seq[string]]()
    try:
        let aliasResponse = await client.host.get("_cat/aliases?h=alias,index")
        for r in aliasResponse.getElems():
            let
                indexName = r{"index"}.getStr()
                aliasName = r{"alias"}.getStr()
            if not result.contains(indexName):
                result[indexName] = newSeq[string]()
            result[indexName].add(aliasName)
    except JsonHttpError as e:
        if e.code == Http404: 
            return 
        raise e
    except:
        raise

proc getIndexList(client: ElasticClient): Future[seq[ElasticIndex]] {.async.} =
    let
        response = await client.host.get("_cat/indices?bytes=b&h=index,health,pri.store.size,creation.date")
        indexAliases = await client.getAliases()

    if response == nil:
        raise newException(JsonHttpError, "Unable to retrieve index list")

    for indexInfo in response.getElems():
        var index = parseIndexInfo indexInfo
        index.aliases = indexAliases.getOrDefault(index.name, @[])
        if index.name != "":
            add(result, index)


proc getRepositoryList(client: ElasticClient): Future[seq[
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

proc getSnapshotList(client: ElasticClient, repository: string): Future[seq[
        ElasticSnapshot]] {.async.} =
    result = newSeq[ElasticSnapshot](0)
    let
        response = await client.host.get(&"_snapshot/{encodeUrl(repository)}/_all")
    if response == nil:
        return
    for snapshotInfo in response["snapshots"].getElems():
        let snapshotInfo = parseSnapshotInfo snapshotInfo
        if snapshotInfo.name != "":
            add(result, snapshotInfo)
    return result


proc removeAlias(client: ElasticClient, index: string, alias: string): Future[
        void] {.async.} =
    discard await client.host.delete(&"/{encodeUrl(index)}/_alias/{encodeUrl(alias)}")

proc removeAlias*(client: ElasticClient, name: string): Future[bool] {.async.} =
    let aliases = await client.getAliases();
    for k, v in aliases:
        if v.contains(name):
            await client.removeAlias(index = k, alias = name)
            return true
    return false

proc createAlias*(client: ElasticClient, index: string, alias: string): Future[void] {.async.} =
    discard await client.host.put(&"/{encodeUrl(index)}/_alias/{encodeUrl(alias)}")

proc removeIndex*(client: ElasticClient, name: string): Future[bool] {.async.} =
    discard await client.host.delete(&"/{encodeUrl(name)}")
    return true

proc removeSnapshot*(client: ElasticClient, repository: string, snapshot: string): Future[bool] {.async.} =
    discard await client.host.delete(&"/_snapshot/{encodeUrl(repository)}/{encodeUrl(snapshot)}")
    return true

proc createSnapshot(client: ElasticClient, repository: string, snapshot: string, indices: seq[string]) : Future[void] {.async.} = 
    let json = %* { 
        "indices": indices.toSeq(),
        "ignore_unavailable": false,
        "include_global_state": false
    }
    let url = &"/_snapshot/{encodeUrl(repository)}/{encodeUrl(snapshot)}?wait_for_completion=true"
    discard await client.host.put(url, json)

proc restoreSnapshot(client: ElasticClient, repository: string,
        snapshotName: string, 
        indexName: string,
        targetName: string): Future[bool] {.async.} =

    try:
        discard await client.removeIndex(targetName)
        discard await client.removeAlias(targetName)
    except:
        discard

    let json = %* {
        "indices": indexName,
        "ignore_unavailable": true,
        "include_global_state": false,
        "rename_pattern": "^.*$",
        "rename_replacement": targetName,
        "include_aliases": false
    };
    discard await client.host.post(
        &"_snapshot/{encodeUrl(repository)}/{encodeUrl(snapshotName)}/_restore" & (if client.wait: "?wait_for_completion=true" else: ""),
        json)
    return true



proc listIndices*(client: ElasticClient): Future[seq[ElasticIndex]] =
    client.getIndexList();

proc listRepositories*(client: ElasticClient): Future[seq[ElasticRepository]] =
    client.getRepositoryList();

proc listSnapshots*(client: ElasticClient, repository: string): Future[seq[ElasticSnapshot]] =
    client.getSnapshotList(repository);

proc backupIndices*(client: ElasticClient, indices: seq[string], repository: string, snapshot: string): Future[void] {.async.} = 
    let 
        existingIndices = (await client.getIndexList()).map((x) => x.name)

    for index in indices:
        if index notin existingIndices:
            raise newException(JsonHttpError, &"Index {index} does not exist")
    
    let repositories = await client.getRepositoryList()
    if not repositories.any(x => x.name == repository):
        raise newException(JsonHttpError, &"Repository {repository} does not exist")

    let snapshots = await client.getSnapshotList(repository)
    if snapshots.any(x => x.name == snapshot):
        raise newException(JsonHttpError, &"Snapshot {snapshot} already exists")

    await client.createSnapshot(repository, snapshot, indices)
    return

proc restoreIndex*(
    client:ElasticClient, 
    repository: string,
    snapshotName: string,
    indexName: string,
    target: string): Future[void] {.async.} = 
    let 
        indices = await client.listIndices()
        indexFound = indices.any((x) => x.name == target)
        (snapshot, snapshotFound) = first(await client.listSnapshots(repository), (x) => x.name == snapshotName)
    var 
        indexName = indexName

    if not snapshotFound:
        raise newException(JsonHttpError, &"Snapshot {snapshotName} does not exist")

    if indexFound:
        raise newException(JsonHttpError, &"Index {indexName} already exists")

    for idx in indices:
        if target in idx.aliases:
            raise newException(JsonHttpError, &"Alias {indexName} already exists. Cannot create index with same name")
    case snapshot.indices.len:
    of 0: raise newException(JsonHttpError, &"Snapshot {snapshotName} contains no indices")
    of 1: 
        if indexName == "": 
            indexName = snapshot.indices[0]
        elif indexName != snapshot.indices[0]:
            raise newException(JsonHttpError, &"Index {indexName} does not exist in snapshot {snapshotName}")
    else:
        if indexName == "":
            raise newException(JsonHttpError, &"Snapshot {snapshotName} contains {snapshot.indices.len} indexes. Please select one")
        if indexName notin snapshot.indices:
            raise newException(JsonHttpError, &"Snapshot {snapshotName} does not contain index {indexName}")
    discard await client.restoreSnapshot(
        repository,
        snapshotName,
        indexName,
        target)

proc makeAlias*(client: ElasticClient, alias: string, index: string): Future[void] {.async.} = 
    discard await client.removeAlias(alias)
    await client.createAlias(alias=alias, index=index)
    await sleepAsync 1
