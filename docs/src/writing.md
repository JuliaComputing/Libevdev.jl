# Writing events (uinput)

```@meta
CurrentModule = Libev
```

[`UinputDevice`](@ref) wraps a kernel `/dev/uinput` virtual input
device. You construct it from a template [`EvdevDevice`](@ref) — the
template's capabilities, identity, and absinfo are cloned onto the
virtual device — then inject events with [`write_event`](@ref). Events
are batched until you call [`syn`](@ref), which flushes them to
consumers.

Creating a uinput device requires permission to open `/dev/uinput`
(typically root or membership in a system-specific group).

## Lifecycle

```@docs
UinputDevice
UinputDevice(::EvdevDevice)
Base.close(::UinputDevice)
Base.isopen(::UinputDevice)
```

## Injecting events

```@docs
write_event
syn
```

## Kernel-assigned paths

```@docs
syspath
devnode
```
