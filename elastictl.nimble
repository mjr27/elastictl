mkDir("dist")

# Package
version       = "0.1.0"
author        = "Kyrylo Kobets"
description   = "Synchronizes elastic indexes with snapshots"
license       = "MIT"
srcDir        = "src"
bin           = @["elastictl"]
binDir        = "dist"

# Dependencies
requires "nim >= 1.2.6"
requires "therapist >= 0.1.0"
requires "yaml >= 0.14.0"
requires "terminaltables"


proc configureRelease() = 
    switch("opt", "size")
    switch("passL", "-s")
    switch("obj_checks", "off")
    switch("field_checks", "off")
    switch("range_checks", "off")
    switch("bound_checks", "off")
    switch("overflow_checks", "off")
    switch("assertions", "off")
    switch("stacktrace", "on")
    switch("linetrace", "off")
    switch("debugger", "off")
    switch("line_dir", "off")
    switch("dead_code_elim", "on")
    switch("debug", "off")
    switch("verbose", "on")

task release, "release build":
    switch("d", "release")
    configureRelease()
    setCommand "build"

task static, "static release build. Musl if possible":
    let exe = findExe("musl-gcc")
    if exe != "":
        switch("gcc.exe", exe)
        switch("gcc.linkerexe", exe)
    switch("passL", "-static")
    configureRelease()
    setCommand "build"