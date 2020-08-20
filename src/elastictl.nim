import asyncdispatch
import logging
import strformat
import uri
import yaml

import elastic/elastic
import ./output/formatted
import ./cl_parser

proc initLogging(logLevel: Level) =
    addHandler(newConsoleLogger(useStderr = true))
    setLogFilter(logLevel)

proc representObject*(value: JsonHttpHost, ts: TagStyle = tsNone,
    c: SerializationContext, tag: TagId) {.raises: [].}  =
    c.put(scalarEvent($(value.root), tag, yAnchorNone))

proc executeCommand(elastic: ElasticClient, command: ConsoleCommand) : Future[void] {.async.} = 
    case command.kind:
    of CommandListIndices:
        formatTableResult(await elastic.listIndices(), command.outputFormat)
    of CommandListRepositories:
        formatTableResult(await elastic.listRepositories(), command.outputFormat)
    of CommandListSnapshots:
        formatTableResult(await elastic.listSnapshots(command.repository), command.outputFormat)
    of CommandRemoveAlias:
        if await elastic.removeAlias(command.rmAliasName):
            info &"Alias {command.rmAliasName} deleted"
        else:
            warn &"Alias {command.rmAliasName} was not found"
    of CommandRemoveIndex:
        if await elastic.removeIndex(command.rmIndexName):
            info &"Index {command.rmIndexName} deleted"
        else:
            warn &"Index {command.rmIndexName} was not found"
    of CommandRemoveSnapshot:
        if await elastic.removeSnapshot(command.repository, command.rmSnapshotName):
            info &"Snapshot {command.rmSnapshotName} deleted"
        else:
            warn &"Snapshot {command.rmSnapshotName} was not found in {command.repository}"
    of CommandBackup:
        await elastic.backupIndices(
            command.backupIndices, 
            command.repository, 
            command.backupSnapshot)
        info &"Snapshot {command.repository}/{command.backupSnapshot} created successfully"
    of CommandRestore:
        let target = if command.restoreTargetIndexName == "" : command.restoreSnapshot else: command.restoreTargetIndexName
        await elastic.restoreIndex(
            command.repository, 
            command.restoreSnapshot,
            command.restoreSnapshotIndexName,
            target)
        warn &"Snapshot {command.repository}/{command.restoreSnapshot}[{command.restoreSnapshotIndexName}] was successfully restored to '{target}'"
    of CommandMakeAlias: 
        await elastic.makeAlias(command.aliasName, command.aliasIndex)
        warn &"Alias {command.aliasName} now points to {command.aliasIndex}"
    of CommandWatch: 
        logging.error "Unknown command"
        failWithHelp()
    of CommandUnknown: 
        logging.error "Unknown command"
        failWithHelp()

proc main() = 
    let command = parseCommandLine()

    initLogging(command.logLevel)
    try:
        var elastic = newClient(command.host, command.wait) # , repository=SNAPSHOT_REPOSITORY, index=TARGET_INDEX_NAME
        waitFor(executeCommand(elastic, command))
    except JsonHttpError as e:
        logging.error $(e.name)
        logging.error $(e.msg)
        quit 1

when isMainModule: main()
