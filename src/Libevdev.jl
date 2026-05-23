module Libevdev

include("LibevdevRaw.jl")
using .LibevdevRaw

# Parse the kernel input headers at precompile time and define matching
# `const` bindings (EV_*, KEY_*, BTN_*, ABS_*, FF_*, MT_TOOL_*, BUS_*,
# ID_*, ...) directly in this module. `include_dependency` makes Julia
# rebuild the precompile cache whenever a header changes — e.g. after a
# kernel-headers upgrade. No Clang.jl involvement: this is a pure regex
# + Meta.parse pass over ~1300 lines of C across two headers.
include("parse_event_codes.jl")

# Constants the wrapper code in this module references directly. The
# precompile-time check below verifies each one was emitted by the
# parser; any failure surfaces at module load with the exact missing
# names, rather than at first call against a stale ABI literal.
const _REQUIRED_KERNEL_CONSTANTS = (:EV_SYN, :EV_ABS, :EV_REL,
                                    :SYN_REPORT, :SYN_DROPPED,
                                    :ABS_MAX, :REL_MAX)

let paths = _find_kernel_headers()
    defined = Symbol[]
    for p in paths
        include_dependency(p)
        append!(defined, _parse_event_codes!(@__MODULE__, p))
    end
    missing_syms = [s for s in _REQUIRED_KERNEL_CONSTANTS
                       if !isdefined(@__MODULE__, s)]
    if !isempty(missing_syms)
        error("""
        Header parser failed to produce required kernel constant(s):
        $(join(missing_syms, ", ")).

        Parsed headers:
            $(join(paths, "\n            "))
        These were probably truncated or otherwise malformed.

        To recover: reinstall your distribution's kernel-headers
        package, replace the bundled fallback at `deps/`, or point
        Libevdev at a known-good copy via the JULIA_LIBEVDEV_KERNEL_HEADERS
        environment variable.
        """)
    end
    for sym in defined
        @eval export $sym
    end
end

include("types.jl")
include("device.jl")
include("read.jl")
include("uinput.jl")
include("props.jl")
include("axis_tracker.jl")

export EvdevDevice, UinputDevice, InputEvent, EvdevError,
       read_event, events, event_channel,
       write_event, syn, syspath, devnode,
       name, phys, uniq, vendor_id, product_id, bustype, version, driver_version,
       has_event, has_property, grab, ungrab, abs_info,
       set_name!, set_phys!, set_uniq!,
       set_vendor_id!, set_product_id!, set_bustype!, set_version!,
       enable_event!, disable_event!, enable_property!, disable_property!,
       set_abs_info!,
       AxisTracker, AxisRange,
       axis, axis_values, axis_range, axis_codes,
       rel, rel_values, rel_codes, consume_rel!, consume_rel_values!,
       tracker_status

end # module Libevdev
