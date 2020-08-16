import os, logging, strutils, therapist, uri

import ./elastic/json_http
import ./elastic/client
import ./output/formatted
type
    CommandKind* = enum
        unknown
        lsIndices
        lsSnapshots
        lsRepos
        rmAlias
        rmIndex
        rmSnapshot
    ConsoleCommand* = object
        outputFormat*: FormatKind
        host*: JsonHttpHost
        logLevel*: logging.Level
        case kind*: CommandKind:
        of unknown: discard
        of lsIndices:
            indexStatus*: string
        of lsSnapshots:
            repository*: string
        of lsRepos:
            discard
        of rmAlias:
            rmAliasName*: string
        of rmIndex:
            rmIndexName*: string
        of rmSnapshot:
            rmSnapshotRepo*: string
            rmSnapshotName*: string

proc parseFormatArg(value: string): FormatKind = parseEnum[FormatKind](value)
defineArg[FormatKind](FormatArg, newFormatArg, "format", parseFormatArg,
        FormatKind.Table)

let LS_INDICES_SPEC = (
    status: newStringArg(@["-s"], help = "Index status",
        choices = @[toLower $(ElasticIndexState.Green), toLower $(ElasticIndexState.Yellow), toLower $(ElasticIndexState.Red)]),
    help: newHelpArg(),
)

let LS_SNAPSHOTS_SPEC = (
    repository: newStringArg(@["-r", "--repository"], env = "ELASTIC_REPOSITORY",
    help = "Repository [$ELASTIC_REPOSITORY]", default = "backup"),
        help: newHelpArg(),
)

let LS_SPEC = (
    indices: newCommandArg(
        @["indices"], 
        LS_INDICES_SPEC,
        help = "List elastic indices"),

    repos: newCommandArg(@["repos"], (help: newHelpArg()),
        help = "List repositories"),
    snapshots: newCommandArg(@["snapshots"], LS_SNAPSHOTS_SPEC,
        help = "List elastic snapshots"),
    help: newHelpArg(),
)


let RM_ALIAS_SPEC = (
    name: newStringArg(@["<name>"], required = true,
        help = "Alias name to delete"),
    help: newHelpArg(),
)

let RM_INDEX_SPEC = (
    name: newStringArg(@["<name>"], required = true,
        help = "Index name to delete"),
    help: newHelpArg(),
)
let RM_SNAPSHOT_SPEC = (
    repository: newStringArg(@["<repository>"], required = true,  help = "Repository name"),
    snapshot: newStringArg(@["<name>"], required = true,  help = "Snapshot name"),
    help: newHelpArg(),
)

let DELETE_SPEC = (
    alias: newCommandArg(@["alias"], RM_ALIAS_SPEC, help = "Delete alias"),
    index: newCommandArg(@["index"], RM_INDEX_SPEC, help = "Delete index"),
    snapshot: newCommandArg(@["snapshot"], RM_SNAPSHOT_SPEC, help = "Delete snapshot"),
    help: newHelpArg(),
)

let spec = (
    list: newCommandArg(
        @["ls", "list"], LS_SPEC, help = "List resources"),
    delete: newCommandArg(
        @["rm", "remove", "del", "delete"], 
        DELETE_SPEC,
        help = "Delete resources"),

    format: newFormatArg(@["--format"], help = "Display format"),
        elasticHost: newURLArg(@["--elastic-host"], env = "ELASTIC_HOST",
        defaultVal = parseUri("http://localhost:9200"),
    help = "Elastic URI [$ELASTIC_HOST]"),
        elasticUser: newStringArg(@["-u", "--elastic-username"],
        env = "ELASTIC_USERNAME", default = "elastic",
        help = "Elastic username [$ELASTIC_USERNAME]"),
    elasticPassword: newStringArg(@["-p", "--elastic-password"],
        env = "ELASTIC_PASSWORD",
        help = "Elastic password [$ELASTIC_PASSWORD]"),
        verbose: newCountArg(@["-v", "--verbose"], help = "Verbose output", ),
    help: newHelpArg()
)

proc failWithHelp*() = spec.parseOrQuit(prolog = "Elastic index sync",
        command = "elasticindexsync", args = "--help")
proc parseCommandLine*(): ConsoleCommand =
    spec.parseOrQuit(prolog = "Elastic index sync",
            command = "elasticindexsync")
    if spec.list.seen:
        if LS_SPEC.indices.seen:
            result = ConsoleCommand(kind: CommandKind.lsIndices,
                    indexStatus: LS_INDICES_SPEC.status.value)
        elif LS_SPEC.snapshots.seen:
            result = ConsoleCommand(kind: CommandKind.lsSnapshots,
                    repository: LS_SNAPSHOTS_SPEC.repository.value)
        elif LS_SPEC.repos.seen:
            result = ConsoleCommand(kind: CommandKind.lsRepos)
        else:
            failWithHelp()
    elif spec.delete.seen:
        if DELETE_SPEC.alias.seen:
            result = ConsoleCommand(kind: CommandKind.rmAlias,
                rmAliasName: RM_ALIAS_SPEC.name.value)
        if DELETE_SPEC.index.seen:
            result = ConsoleCommand(kind: CommandKind.rmIndex,
                rmIndexName: RM_ALIAS_SPEC.name.value)
        if DELETE_SPEC.snapshot.seen:
            result = ConsoleCommand(kind: CommandKind.rmSnapshot,
                rmSnapshotRepo: RM_SNAPSHOT_SPEC.repository.value,
                rmSnapshotName: RM_SNAPSHOT_SPEC.snapshot.value)
        else:
            failWithHelp()
    else:
        failWithHelp()
    result.outputFormat = spec.format.value
    result.host = newJsonHost(host = spec.elasticHost.value,
            user = spec.elasticUser.value,
            password = spec.elasticPassword.value)
    result.logLevel = case spec.verbose.count
        of 0: lvlWarn
        of 1: lvlInfo
        else: lvlAll
