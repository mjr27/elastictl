# Package
version       = "0.1.0"
author        = "Kyrylo Kobets"
description   = "Synchronizes elastic indexes with snapshots"
license       = "MIT"
srcDir        = "src"
bin           = @["elasticindexsync"]

# Dependencies
requires "nim >= 1.2.6"
requires "therapist >= 0.1.0"
requires "yaml >= 0.14.0"
requires "terminaltables"
# requires "cligen"