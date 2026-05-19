# Devices

```@meta
CurrentModule = Libev
```

The [`EvdevDevice`](@ref) type is the central handle: it owns a libevdev
context plus an open file descriptor to a `/dev/input/eventN` node, and
guards them with a per-device lock so the same device can be safely
shared across tasks.

## Lifecycle

```@docs
EvdevDevice
EvdevDevice(::AbstractString)
EvdevDevice(::Base.RawFD)
Base.open(::Type{EvdevDevice}, ::AbstractString)
Base.close(::EvdevDevice)
Base.isopen(::EvdevDevice)
```

## Identity

```@docs
name
phys
uniq
vendor_id
product_id
bustype
version
driver_version
```

## Capabilities

```@docs
has_event
has_property
abs_info
```

## Exclusive access

```@docs
grab
ungrab
```

## Errors

```@docs
EvdevError
```
