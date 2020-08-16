import asyncdispatch
import strformat
import logging
import strutils
import uri
import ./elastic/json_http
import yaml

import ./elastic/client
import ./output/formatted
import ./cl_parser

# const ELASTIC_USER = "elastic";
# const ELASTIC_PASSWORD = "1Y2zLwmDE87uCpbjzph8pnEZ1b4kWvqz";
# const SNAPSHOT_REPOSITORY = "backup";
# const TARGET_INDEX_NAME = "egw";

proc initLogging(logLevel: Level) =
    addHandler(newConsoleLogger(useStderr = true))
    setLogFilter(logLevel)

proc listIndices(client: ElasticClient): seq[ElasticIndex] =
    waitFor(client.getIndexList());

proc listRepositories(client: ElasticClient): seq[ElasticRepository] =
    waitFor(client.getRepositoryList());

proc listSnapshots(client: ElasticClient, repository: string): seq[
        ElasticSnapshot] =
    waitFor(client.getSnapshotList(repository));

proc representObject*(value: JsonHttpHost, ts: TagStyle = tsNone,
    c: SerializationContext, tag: TagId) {.raises: [].}  =
    echo $(value.root)
    c.put(scalarEvent($(value.root), tag, yAnchorNone))

proc processCommand(command: ConsoleCommand) = 
    var elastic = newClient(command.host) # , repository=SNAPSHOT_REPOSITORY, index=TARGET_INDEX_NAME
    case command.kind:
    of lsIndices:
        formatTableResult(elastic.listIndices(), command.outputFormat)
    of lsRepos:
        formatTableResult(elastic.listRepositories(), command.outputFormat)
    of lsSnapshots:
        formatTableResult(elastic.listSnapshots(command.repository),
            command.outputFormat)
    of rmAlias:
        if waitFor(elastic.removeAlias(command.rmAliasName)):
            info &"Alias {command.rmAliasName} deleted"
        else:
            warn &"Alias {command.rmAliasName} was not found"
    of rmIndex:
        if waitFor(elastic.removeIndex(command.rmIndexName)):
            info &"Index {command.rmIndexName} deleted"
        else:
            warn &"Index {command.rmIndexName} was not found"
    of rmSnapshot:
        if waitFor(elastic.removeSnapshot(command.rmSnapshotRepo, command.rmSnapshotName)):
            info &"Snapshot {command.rmSnapshotName} deleted"
        else:
            warn &"Snapshot {command.rmSnapshotName} was not found in {command.rmSnapshotRepo}"
    # of CommandKind.lsSnapshots: echo "ls snapshots ", command.format
    else: 
        logging.error "Unknown command"
        echo yaml.dump(command)
        failWithHelp()


when isMainModule:
    when true:
        let command = parseCommandLine()

        initLogging(command.logLevel)
        try:
            processCommand command
        except JsonHttpError as e:
            echo "<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<"
            logging.error $(e.name)
            echo "<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<"
            logging.error $(e.msg)
            # error $e.msg
            echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
            quit 1
    else:
        import cligen
        proc lsIndexes() =
            echo "done"
        dispatchMulti [lsIndexes]

