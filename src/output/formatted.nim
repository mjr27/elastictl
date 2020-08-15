import json
import strutils
import tables
import terminalTables
import times
import yaml

type
    FormatKind* = enum
        Table
        Json
        Yaml

proc makeStr(s: string): string = s
proc makeStr(i: int|int64|float|enum): string = $i
proc makeStr(i: Time): string = $(i)
proc makeStr(s: openArray[string]): string = join(s, ", ")

proc dumpJson[T](data: T): string = dump(data, tsNone, asNone, defineOptions(
    style = psJson))
proc dumpYaml[T](data: T): string = dump(data, tsNone, asNone, defineOptions(
    style = psDefault))
proc dumpTable[T](data: seq[T]): string =
    let table = newUnicodeTable()
    var
        headers = newSeq[string]()
        x: T;

    table.separateRows = false
    for k, v in x.fieldPairs:
        headers.add(k)
    table.setHeaders(headers)

    for element in data:
        var row = newSeq[string]()
        for v in element.fields:
            row.add makeStr(v)
        table.addRow(row)

    table.render()

proc formatTableResult*[T](data: seq[T], format: FormatKind) =
    case format
    of FormatKind.Table:
        echo dumpTable(data)
    of FormatKind.Json:
        echo dumpJson(data)
        discard
    of FormatKind.Yaml:
        echo dumpYaml(data)
        discard
