# Lightweight precompile-time parser for the Linux input subsystem's
# kernel headers — `linux/input-event-codes.h` and `linux/input.h`.
#
# Runs at module-load time (precompilation) and emits the kernel input
# constants as plain `const` definitions in the calling module. The
# parser handles object-like `#define NAME EXPR` lines, where EXPR is
# an integer literal, hex literal, simple arithmetic expression, or
# alias to a previously-defined name — everything `Meta.parse` accepts.
# The regex requires whitespace after the name and `Meta.parse` /
# `Base.eval` are wrapped in try/catch, so function-like macros,
# `_IOR`/`_IOW` ioctl definitions, struct declarations, and any other
# content the parser can't make sense of are passed over silently,
# letting precompilation continue with the rest of the file.

const _CODES_PREFIXES = ("EV_", "KEY_", "BTN_", "ABS_", "REL_", "SYN_",
                        "MSC_", "LED_", "REP_", "SND_", "INPUT_PROP_",
                        "SW_", "MT_TOOL_", "FF_", "BUS_", "ID_")

const _BUNDLED_HEADERS_DIR = normpath(joinpath(@__DIR__, "..", "deps"))

# Each entry pairs the relative path under /usr/include/linux with a
# bundled-fallback basename. Parse order matters when one header
# references a constant defined by an earlier one; our two headers
# are independent of each other, so the listed order is just for
# stable output.
const _KERNEL_HEADERS = (
    ("input-event-codes.h", "input-event-codes.h"),
    ("input.h",             "input.h"),
)

"""
Name of the environment variable users can set to override where Libevdev
looks for the kernel input headers. The value is a directory
containing both `input-event-codes.h` and `input.h`. Libevdev pulls each
header from this directory first, then the system path, then the
multiarch system path, then the bundled `deps/` copy.

Precompile caches must be manually invalidated when this variable
changes — `Pkg.precompile(strict=true)` or
`rm ~/.julia/compiled/v*/Libevdev`.
"""
const _ENV_OVERRIDE = "JULIA_LIBEVDEV_KERNEL_HEADERS"

# Resolve each kernel input header by checking, in order:
#   1. $JULIA_LIBEVDEV_KERNEL_HEADERS/<rel>   — user override
#   2. /usr/include/linux/<rel>            — system path
#   3. /usr/include/x86_64-linux-gnu/linux/<rel> — multiarch system path
#   4. deps/<fallback>                     — package-bundled copy
function _find_kernel_headers()
    paths = String[]
    user_dir = get(ENV, _ENV_OVERRIDE, "")
    for (rel, fallback) in _KERNEL_HEADERS
        candidates = String[]
        isempty(user_dir) || push!(candidates, joinpath(user_dir, rel))
        push!(candidates, "/usr/include/linux/" * rel)
        push!(candidates, "/usr/include/x86_64-linux-gnu/linux/" * rel)
        push!(candidates, joinpath(_BUNDLED_HEADERS_DIR, fallback))
        found = nothing
        for c in candidates
            if isfile(c); found = c; break; end
        end
        if found === nothing
            override_note = isempty(user_dir) ? "" :
                "\n            (\$$_ENV_OVERRIDE is set to $(repr(user_dir)); " *
                "no `$rel` was found in that directory.)"
            error("""
            Cannot locate linux/$rel.$override_note

            Either install your distribution's kernel-headers package
            (`apt install linux-libc-dev`, `dnf install kernel-headers`, ...),
            set the $_ENV_OVERRIDE environment variable to a directory
            containing the kernel input headers, or place a copy at:
                $(joinpath(_BUNDLED_HEADERS_DIR, fallback))
            """)
        end
        push!(paths, found)
    end
    return paths
end

# Strip C `/* ... */` and `// ...` comments. Both forms appear in
# input.h and input-event-codes.h.
function _strip_c_comments(text::AbstractString)
    text = replace(text, r"/\*.*?\*/"s => "")
    text = replace(text, r"//[^\n]*" => "")
    return text
end

"""
    _parse_event_codes!(mod, path, prefixes = _CODES_PREFIXES) -> Vector{Symbol}

Parse the C header at `path` and define matching `#define`d constants
in `mod`. Returns a list of `Symbol`s actually defined, so the caller
can export them.

The regex requires at least one space between the name and the value,
matching object-like `#define`s (`#define KEY_A 30`) while passing
over function-like macros (`#define foo(x) ...`), which have `(`
flush against the name. The `Base.eval` call is wrapped in
`try`/`catch`, so a line whose RHS references an undefined name, is a
non-evalable C construct, or otherwise surprises us is skipped and
precompilation continues with the next line.
"""
function _parse_event_codes!(mod::Module, path::AbstractString,
                            prefixes::NTuple{N,String}=_CODES_PREFIXES) where N
    text = _strip_c_comments(read(path, String))
    define_re = r"^[ \t]*#[ \t]*define[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]+(.+?)[ \t]*$"m
    defined = Symbol[]
    for m in eachmatch(define_re, text)
        name = m.captures[1]::AbstractString
        any(p -> startswith(name, p), prefixes) || continue
        value_str = strip(m.captures[2]::AbstractString)
        isempty(value_str) && continue
        expr = try
            Meta.parse(value_str)
        catch
            continue
        end
        sym = Symbol(name)
        # Skip if this symbol was already defined by an earlier header
        # (shouldn't happen for our header pair, but guards against
        # surprising redefinition warnings if it ever does).
        isdefined(mod, sym) && continue
        try
            Base.eval(mod, Expr(:const, Expr(:(=), sym, expr)))
            push!(defined, sym)
        catch
            continue
        end
    end
    return defined
end
