using Clang.Generators
using libevdev_jll

cd(@__DIR__)

include_dir = normpath(libevdev_jll.artifact_dir, "include", "libevdev-1.0")
libevdev_dir = joinpath(include_dir, "libevdev")

options = load_options(joinpath(@__DIR__, "generator.toml"))

args = get_default_args()
push!(args, "-I$include_dir")

# Only libevdev's own headers — kernel event-code constants
# (linux/input-event-codes.h) are now parsed at precompile time from a
# bundled / system copy, so this generator does not touch them.
headers = [joinpath(libevdev_dir, header)
           for header in readdir(libevdev_dir) if endswith(header, ".h")]

ctx = create_context(headers, args, options)

build!(ctx)
