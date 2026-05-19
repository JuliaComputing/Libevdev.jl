using Documenter
using Libevdev

makedocs(
    sitename = "Libevdev.jl",
    modules = [Libevdev],
    authors = "Benjamin Chung",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", "false") == "true",
        edit_link = nothing,
        repolink = nothing,
    ),
    pages = [
        "Home" => "index.md",
        "Devices" => "devices.md",
        "Reading events" => "reading.md",
        "Writing events" => "writing.md",
        "Axis tracker" => "tracker.md",
        "Kernel constants" => "constants.md",
        "Internals" => "internals.md",
    ],
    # The kernel-constants flood (700+ bindings re-exported from LibevdevRaw)
    # would generate that many "missing docstring" warnings; suppress
    # missing-docs checking entirely and rely on the per-page autodocs
    # blocks for the wrapper API's coverage.
    checkdocs = :none,
    warnonly = [:cross_references],
    # Not a git repo — disable remote source links. Set `remotes` to a
    # real map (or just remove this line) if/when this project is moved
    # into git and we want "Edit on GitHub" links.
    remotes = nothing,
)
