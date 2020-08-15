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
    ConsoleCommand* = object
        format*: FormatKind
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

proc parseFormatArg(value: string): FormatKind = parseEnum[FormatKind](value)
defineArg[FormatKind](FormatArg, newFormatArg, "format", parseFormatArg,
        FormatKind.Table)

let listIndexOptionsSpec = (
  status: newStringArg(@["-s"], help = "Index status",
    choices = @[toLower $(ElasticIndexState.Green), toLower $(
            ElasticIndexState.Yellow), toLower $(ElasticIndexState.Red)]),
  help: newHelpArg(),
)

let listSnapshotOptionsSpec = (
  repository: newStringArg(@["-r", "--repository"], env = "ELASTIC_REPOSITORY",
          help = "Repository [$ELASTIC_REPOSITORY]", default = "backup"),
  help: newHelpArg(),
)

let listSpec = (
  indices: newCommandArg(@["indices"], listIndexOptionsSpec,
          help = "List elastic indices"),
  repos: newCommandArg(@["repos"], (help: newHelpArg()),
          help = "List repositories"),
  snapshots: newCommandArg(@["snapshots"], listSnapshotOptionsSpec,
          help = "List elastic snapshots"),
  help: newHelpArg(),
)


let deleteAliasSpec = (
  name: newStringArg(@["<name>"], required = true,
          help = "Alias name to delete"),
  help: newHelpArg(),
)

let deleteIndexSpec = (
  name: newStringArg(@["<name>"], required = true,
          help = "Index name to delete"),
  help: newHelpArg(),
)

let deleteSpec = (
  alias: newCommandArg(@["alias"], deleteAliasSpec, help = "Delete alias"),
  index: newCommandArg(@["index"], deleteIndexSpec, help = "Delete index"),
  snapshot: newCommandArg(@["snapshot"], (help: newHelpArg()),
          help = "Delete snapshot"),
    help: newHelpArg(),
)

let spec = (
  list: newCommandArg(@["ls", "list"], listSpec, help = "List resources"),
  delete: newCommandArg(@["rm", "remove", "del", "delete"], deleteSpec,
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

proc failWithHelp() = spec.parseOrQuit(prolog = "Elastic index sync",
        command = "elasticindexsync", args = "--help")
proc parseCommandLine*(): ConsoleCommand =
    spec.parseOrQuit(prolog = "Elastic index sync",
            command = "elasticindexsync")
    if spec.list.seen:
        if listSpec.indices.seen:
            result = ConsoleCommand(kind: CommandKind.lsIndices,
                    indexStatus: listIndexOptionsSpec.status.value)
        elif listSpec.snapshots.seen:
            result = ConsoleCommand(kind: CommandKind.lsSnapshots,
                    repository: listSnapshotOptionsSpec.repository.value)
        elif listSpec.repos.seen:
            result = ConsoleCommand(kind: CommandKind.lsRepos)
        else:
            failWithHelp()
    elif spec.delete.seen:
        if deleteSpec.alias.seen:
            result = ConsoleCommand(kind: CommandKind.rmAlias,
                    rmAliasName: deleteAliasSpec.name.value)
        if deleteSpec.index.seen:
            result = ConsoleCommand(kind: CommandKind.rmIndex,
                    rmIndexName: deleteIndexSpec.name.value)
        else:
            failWithHelp()
    else:
        failWithHelp()
    result.format = spec.format.value
    result.host = newJsonHost(host = spec.elasticHost.value,
            user = spec.elasticUser.value,
            password = spec.elasticPassword.value)
    result.logLevel = case spec.verbose.count
        of 0: lvlWarn
        of 1: lvlInfo
        else: lvlAll
