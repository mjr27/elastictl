import os, logging, strutils, therapist, uri

import elastic/elastic
import output/formatted
type
    CommandKind* = enum
        CommandUnknown
        CommandListIndices
        CommandListSnapshots
        CommandListRepositories
        CommandRemoveAlias
        CommandRemoveIndex
        CommandRemoveSnapshot
        CommandBackup
        CommandRestore
        CommandMakeAlias
        CommandWatch
    ConsoleCommand* = object
        outputFormat*: FormatKind
        host*: JsonHttpHost
        repository*: string
        logLevel*: logging.Level
        wait*: bool
        case kind*: CommandKind:
        of CommandUnknown: discard
        of CommandListIndices:
            indexStatus*: string
        of CommandListSnapshots:
            discard
        of CommandListRepositories:
            discard
        of CommandRemoveAlias:
            rmAliasName*: string
        of CommandRemoveIndex:
            rmIndexName*: string
        of CommandRemoveSnapshot:
            rmSnapshotName*: string
        of CommandBackup:
            backupSnapshot*: string
            backupIndices*: seq[string]
            backupWait* : bool
        of CommandRestore:
            restoreSnapshot*: string
            restoreSnapshotIndexName*: string
            restoreTargetIndexName*: string
            restoreWait* : bool
        of CommandMakeAlias:
            aliasName*: string
            aliasIndex*: string
        of CommandWatch:
            discard

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
        @["indices", "indexes", "idx"], 
        LS_INDICES_SPEC,
        help = "List elastic indices"),

    repos: newCommandArg(@["repositories", "repos"], (help: newHelpArg()),
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
    snapshot: newStringArg(@["<name>"], required = true,  help = "Snapshot name"),
    help: newHelpArg(),
)

let DELETE_SPEC = (
    alias: newCommandArg(@["alias"], RM_ALIAS_SPEC, help = "Delete alias"),
    index: newCommandArg(@["index"], RM_INDEX_SPEC, help = "Delete index"),
    snapshot: newCommandArg(@["snapshot"], RM_SNAPSHOT_SPEC, help = "Delete snapshot"),
    help: newHelpArg(),
)

let BACKUP_SPEC = (
    snapshot: newStringArg(@["<snapshot>"], required=true, help = "Snapshot name"),
    indices: newStringArg(@["<index>"], required=true, multi=true, help="Indexes to back up"),
    help: newHelpArg(),
)

let RESTORE_SPEC = (
    snapshot: newStringArg(@["<snapshot>"], required=true, help = "Snapshot name"),
    index: newStringArg(@["--index", "-i"], required = false,  help = "Index to restore. Should be specified if snapshot contains multiple indices"),
    target: newStringArg(@["--target"], required = false,  help = "Target index to restore to. By default restores to index with the same name as snapshot"),
    wait: newCountArg(@["--wait", "-w"], required = false,  help = "Wait for completion"),
    help: newHelpArg(),
)


let ALIAS_SPEC = (
    alias: newStringArg(@["<alias>"], required=true, help = "Alias name"),
    index: newStringArg(@["<index>"], required = true,  help = "Index to point to"),
    help: newHelpArg(),
)

let WATCH_SPEC = (
    help: newHelpArg(),
)

let spec = (
    list: newCommandArg(
        @["ls", "list"], LS_SPEC, help = "List resources"),
    delete: newCommandArg(
        @["rm", "remove", "del", "delete"], 
        DELETE_SPEC,
        help = "Delete resources"),
    backup: newCommandArg(
        @["backup"],
        BACKUP_SPEC,
        help = "Backup multiple indices"),
    restore: newCommandArg(
        @["restore"],
        RESTORE_SPEC,
        help = "Restore a snapshot"),
    alias: newCommandArg(
        @["alias"],
        ALIAS_SPEC,
        help = "Make alias"),
    watch: newCommandArg(
        @["watch"],
        WATCH_SPEC,
        help = "Watch for new snapshots"),
    format: newFormatArg(@["--format"], help = "Display format"),
    repository: newStringArg(@["--repository", "-r"], help = "Backup/restore repository [$ELASTIC_REPOSITORY]", 
        default= "backup", 
        env="ELASTIC_REPOSITORY"),
    elasticHost: newURLArg(@["--elastic-host"], env = "ELASTIC_HOST",
        defaultVal = parseUri("http://localhost:9200"),
        help = "Elastic URI [$ELASTIC_HOST]"),
    elasticUser: newStringArg(@["-u", "--elastic-username"],
        env = "ELASTIC_USERNAME", default = "elastic",
        help = "Elastic username [$ELASTIC_USERNAME]"),
    elasticPassword: newStringArg(@["-p", "--elastic-password"],
        env = "ELASTIC_PASSWORD",
        help = "Elastic password [$ELASTIC_PASSWORD]"),
    wait: newCountArg(@["--wait", "-w"], required = false,  help = "Wait for completion"),
    verbose: newCountArg(@["-v", "--verbose"], help = "Verbose output. May be specified multiple times", ),
    help: newHelpArg()
)

proc failWithHelp*() = spec.parseOrQuit(prolog = "Elastic index sync",
        command = paramStr(0), args = "--help")
proc parseCommandLine*(): ConsoleCommand =
    spec.parseOrQuit(prolog = "Elastic index sync",
            command = "elasticindexsync")
    if spec.list.seen:
        if LS_SPEC.indices.seen:
            result = ConsoleCommand(kind: CommandKind.CommandListIndices,
                    indexStatus: LS_INDICES_SPEC.status.value)
        elif LS_SPEC.snapshots.seen:
            result = ConsoleCommand(kind: CommandKind.CommandListSnapshots,
                    repository: LS_SNAPSHOTS_SPEC.repository.value)
        elif LS_SPEC.repos.seen:
            result = ConsoleCommand(kind: CommandKind.CommandListRepositories)
    elif spec.delete.seen:
        if DELETE_SPEC.alias.seen:
            result = ConsoleCommand(kind: CommandKind.CommandRemoveAlias,
                rmAliasName: RM_ALIAS_SPEC.name.value)
        if DELETE_SPEC.index.seen:
            result = ConsoleCommand(kind: CommandKind.CommandRemoveIndex,
                rmIndexName: RM_INDEX_SPEC.name.value)
        if DELETE_SPEC.snapshot.seen:
            result = ConsoleCommand(kind: CommandKind.CommandRemoveSnapshot,
                rmSnapshotName: RM_SNAPSHOT_SPEC.snapshot.value)
    elif spec.backup.seen:
        result = ConsoleCommand(
            kind:CommandKind.CommandBackup,
            backupIndices: BACKUP_SPEC.indices.values,
            backupSnapshot: BACKUP_SPEC.snapshot.value)
    elif spec.restore.seen:
        result = ConsoleCommand(
            kind:CommandKind.CommandRestore,
            # index
            # target
            restoreSnapshot: RESTORE_SPEC.snapshot.value,
            restoreSnapshotIndexName: RESTORE_SPEC.index.value,
            restoreTargetIndexName: RESTORE_SPEC.target.value)
    elif spec.alias.seen:
        result = ConsoleCommand(
            kind:CommandKind.CommandMakeAlias,
            aliasName: ALIAS_SPEC.alias.value,
            aliasIndex: ALIAS_SPEC.index.value,
            wait: RESTORE_SPEC.wait.count > 0)
    elif spec.watch.seen:
        result = ConsoleCommand(kind:CommandKind.CommandWatch)
    result.outputFormat = spec.format.value
    result.host = newJsonHost(host = spec.elasticHost.value,
            user = spec.elasticUser.value,
            password = spec.elasticPassword.value)
    result.repository = spec.repository.value
    result.wait = spec.wait.count > 0
    result.logLevel = case spec.verbose.count
        of 0: lvlWarn
        of 1: lvlInfo
        else: lvlAll
