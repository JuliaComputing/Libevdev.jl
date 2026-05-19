# Property / capability / identity accessors. All wrappers hold
# `dev.lock` for the duration of the ccall; results are converted to
# idiomatic Julia types (`String`/`nothing` for possibly-null C strings,
# `Int` for the small-int getters, `Bool` for predicates).

# Local mirror of the kernel's `struct input_absinfo`. The generated
# bindings hand back Ptr{Cvoid} for libevdev_get_abs_info, so we define
# the layout here for `unsafe_load`. Matches the kernel ABI on every
# Linux platform libevdev supports.
struct input_absinfo
    value::Int32
    minimum::Int32
    maximum::Int32
    fuzz::Int32
    flat::Int32
    resolution::Int32
end

# Convert a possibly-null Ptr to Union{String, Nothing} without an
# extra copy.
@inline function _cstring_or_nothing(p::Ptr)
    return p == C_NULL ? nothing : unsafe_string(Ptr{UInt8}(p))
end

"""
    name(dev::EvdevDevice) -> Union{String, Nothing}

Human-readable device name (e.g. `"AT Translated Set 2 keyboard"`).

# Returns
The name as a `String`, or `nothing` if the device has no name set.
"""
function name(dev::EvdevDevice)
    return lock(dev.lock) do
        _cstring_or_nothing(LibEvdev.libevdev_get_name(dev))
    end
end

"""
    phys(dev::EvdevDevice) -> Union{String, Nothing}

Physical (topological) location of the device, e.g.
`"usb-0000:00:14.0-1/input0"`.

# Returns
The location as a `String`, or `nothing` if unset.
"""
function phys(dev::EvdevDevice)
    return lock(dev.lock) do
        _cstring_or_nothing(LibEvdev.libevdev_get_phys(dev))
    end
end

"""
    uniq(dev::EvdevDevice) -> Union{String, Nothing}

Unique identifier reported by the device (often empty / `nothing`).
"""
function uniq(dev::EvdevDevice)
    return lock(dev.lock) do
        _cstring_or_nothing(LibEvdev.libevdev_get_uniq(dev))
    end
end

"""
    vendor_id(dev::EvdevDevice) -> Int

USB / PCI vendor ID.
"""
vendor_id(dev::EvdevDevice) = lock(dev.lock) do
    Int(LibEvdev.libevdev_get_id_vendor(dev))
end

"""
    product_id(dev::EvdevDevice) -> Int

USB / PCI product ID.
"""
product_id(dev::EvdevDevice) = lock(dev.lock) do
    Int(LibEvdev.libevdev_get_id_product(dev))
end

"""
    bustype(dev::EvdevDevice) -> Int

Bus type identifier. One of the kernel `BUS_*` constants from
`<linux/input.h>` (e.g. `BUS_USB = 3`, `BUS_PCI = 1`).
"""
bustype(dev::EvdevDevice) = lock(dev.lock) do
    Int(LibEvdev.libevdev_get_id_bustype(dev))
end

"""
    version(dev::EvdevDevice) -> Int

Device firmware/protocol version reported by the driver.
"""
version(dev::EvdevDevice) = lock(dev.lock) do
    Int(LibEvdev.libevdev_get_id_version(dev))
end

"""
    driver_version(dev::EvdevDevice) -> Int

Input subsystem protocol version (`EVIOCGVERSION`).
"""
driver_version(dev::EvdevDevice) = lock(dev.lock) do
    Int(LibEvdev.libevdev_get_driver_version(dev))
end

"""
    has_event(dev::EvdevDevice, type::Integer, code::Integer=-1) -> Bool

Query whether the device advertises the given event class.

# Arguments
- `type`: event type code (`EV_KEY`, `EV_ABS`, ...).
- `code`: type-specific code. When `code < 0` (default), queries whether
  the device emits *any* event of `type`; otherwise queries the specific
  `(type, code)` pair.

# Returns
`true` if the capability is advertised, `false` otherwise.
"""
function has_event(dev::EvdevDevice, type::Integer, code::Integer=-1)
    return lock(dev.lock) do
        if code < 0
            LibEvdev.libevdev_has_event_type(dev, Cuint(type)) != 0
        else
            LibEvdev.libevdev_has_event_code(dev, Cuint(type), Cuint(code)) != 0
        end
    end
end

"""
    has_property(dev::EvdevDevice, prop::Integer) -> Bool

Query whether the device has the given input property (`INPUT_PROP_*`
from `<linux/input-event-codes.h>`).
"""
function has_property(dev::EvdevDevice, prop::Integer)
    return lock(dev.lock) do
        LibEvdev.libevdev_has_property(dev, Cuint(prop)) != 0
    end
end

"""
    grab(dev::EvdevDevice)

Acquire exclusive access to the device (`EVIOCGRAB`). While grabbed,
this process is the sole receiver of events from the device.

# Throws
- `EvdevError` if another process already holds an exclusive grab.
"""
function grab(dev::EvdevDevice)
    lock(dev.lock) do
        check(LibEvdev.libevdev_grab(dev, LibEvdev.LIBEVDEV_GRAB), "libevdev_grab")
    end
    return nothing
end

"""
    ungrab(dev::EvdevDevice)

Release a prior [`grab`](@ref).
"""
function ungrab(dev::EvdevDevice)
    lock(dev.lock) do
        check(LibEvdev.libevdev_grab(dev, LibEvdev.LIBEVDEV_UNGRAB),
              "libevdev_grab(UNGRAB)")
    end
    return nothing
end

"""
    abs_info(dev::EvdevDevice, code::Integer) -> NamedTuple

Return the `EV_ABS` axis description for `code`.

# Returns
A `NamedTuple` with fields `minimum`, `maximum`, `fuzz`, `flat`,
`resolution` (all `Int`), as reported by the kernel `EVIOCGABS` ioctl.

# Throws
- `EvdevError` (with `errno = ENOENT`) if the device doesn't expose
  that axis (libevdev returns NULL).
"""
function abs_info(dev::EvdevDevice, code::Integer)
    return lock(dev.lock) do
        p = LibEvdev.libevdev_get_abs_info(dev, Cuint(code))
        if p == C_NULL
            throw(EvdevError(Int32(Libc.ENOENT), "libevdev_get_abs_info(code=$code)"))
        end
        info = unsafe_load(Ptr{input_absinfo}(p))
        (minimum=Int(info.minimum),
         maximum=Int(info.maximum),
         fuzz=Int(info.fuzz),
         flat=Int(info.flat),
         resolution=Int(info.resolution))
    end
end
