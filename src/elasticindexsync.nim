import os
import strformat
import logging
import httpcore
import strutils

import ./elasticclient

const ELASTIC_USER = "elastic";
const ELASTIC_PASSWORD = "1Y2zLwmDE87uCpbjzph8pnEZ1b4kWvqz";
const SNAPSHOT_REPOSITORY = "backup";
const TARGET_INDEX_NAME = "egw";

proc init() = 
  addHandler(newConsoleLogger(lvlInfo))

proc run() = 
  try:
    var host = newHost(user=ELASTIC_USER, password=ELASTIC_PASSWORD)
    var client = newClient(host, repository=SNAPSHOT_REPOSITORY, index=TARGET_INDEX_NAME)
    let indexList = client.getIndexList()
    let snapshotList = client.getSnapshotList()
    info &"Index list: {indexList}"
    info &"Snapshot list: {snapshotList}"
    for snapshot in snapshotList:
      if not indexList.contains(snapshot):
        info("Restoring ", snapshot)
        discard restoreSnapshot(client, snapshot)
  except ElasticHttpError as e:
    error("Error while updating: ", e.msg.strip)

proc finalize() = discard

when isMainModule:
  init()
  while true:
    run()
    sleep 500
    break
  finalize()

