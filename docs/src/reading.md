# Reading events

```@meta
CurrentModule = Libevdev
```

Three layers of API are provided, each useful for a different style of
consumer:

| API | When to use |
|-----|-------------|
| [`read_event`](@ref) | One event at a time, blocking or non-blocking. |
| [`events`](@ref) | A `for ev in events(dev) ... end` loop in the caller's task. |
| [`event_channel`](@ref) | Fan-out to one or more channel consumers, possibly on other threads. |

All three transparently handle `SYN_DROPPED` by entering libevdev's
SYNC drain mode and yielding the synthesized state-delta events
inline. The iterator and channel layers do this automatically;
[`read_event`](@ref) returns the `SYN_DROPPED` event itself and leaves
draining to the caller, which typically means switching to
[`events`](@ref).

## The event type

```@docs
InputEvent
```

## Single-event read

```@docs
read_event
```

## Iterator

```@docs
events
Libevdev.EventIterator
```

## Channel pump

```@docs
event_channel
```
