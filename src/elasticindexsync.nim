import asyncdispatch
import strformat
import logging
import strutils
import yaml

import ./elastic/client
import ./output/formatted
import ./cl_parser

# const ELASTIC_USER = "elastic";
# const ELASTIC_PASSWORD = "1Y2zLwmDE87uCpbjzph8pnEZ1b4kWvqz";
# const SNAPSHOT_REPOSITORY = "backup";
# const TARGET_INDEX_NAME = "egw";

proc initLogging(logLevel: Level) =
    addHandler(newConsoleLogger())
    setLogFilter(logLevel)

proc listIndices(client: ElasticClient): seq[ElasticIndex] =
    waitFor(client.getIndexList());

proc listRepositories(client: ElasticClient): seq[ElasticRepository] =
    waitFor(client.getRepositoryList());

proc listSnapshots(client: ElasticClient, repository: string): seq[
        ElasticSnapshot] =
    waitFor(client.getSnapshotList(repository));


when isMainModule:
    when true:
        let command = parseCommandLine()

        initLogging(command.logLevel)
        var elastic = newClient(command.host) # , repository=SNAPSHOT_REPOSITORY, index=TARGET_INDEX_NAME
        case command.kind:
        of lsIndices:
            formatTableResult(elastic.listIndices(), command.format)
        of lsRepos:
            formatTableResult(elastic.listRepositories(), command.format)
        of lsSnapshots:
            formatTableResult(elastic.listSnapshots(command.repository),
                command.format)
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
        # of CommandKind.lsSnapshots: echo "ls snapshots ", command.format
        else: echo "unknown"
    else:
        import cligen
        proc lsIndexes() =
            echo "done"
        dispatchMulti [lsIndexes]

