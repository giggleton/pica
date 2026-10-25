# Process boundaries (OTP)

**Load when** any changed file matches:

```bash
rg -l 'use GenServer|use Agent|use Task|Task\.(async|start|await)|spawn|Registry|DynamicSupervisor' <changed files>
```

## The rule

A process is a concurrency and lifetime primitive, not a home for domain logic. `handle_call/3`,
`handle_cast/2`, and `handle_info/2` are the same kind of boundary as a LiveView callback:
receive a message, call a context function, update state, reply.

The two questions this check exists to ask: **is the logic in the right place**, and **is the
state safe where it lives**. The second matters more — process state disappears on restart, and
that failure is silent.

## Findings

### 1. Durable state living only in process memory — High

State a GenServer or Agent holds that the system would be wrong to lose, with no persistence
behind it.

```elixir
# finding
def handle_call({:add_credits, user_id, amount}, _from, state) do
  {:reply, :ok, Map.update(state, user_id, amount, &(&1 + amount))}
end
```

The process crashes, the supervisor restarts it clean, and the credits are gone with no error
anywhere. This is the highest-value finding in the file because nothing surfaces it — tests
pass, logs are quiet, and the data is simply wrong afterwards.

Ask what a restart costs. Caches, rate-limiter buckets, and connection state are fine to lose
by design and are not findings. Anything a user or an invoice depends on belongs in the
persistence layer, with the process holding at most a cached copy.

### 2. Business logic inside callbacks — Medium

Domain decisions computed in `handle_call/3` or `handle_cast/2` rather than delegated to a
context.

```elixir
# finding
def handle_call({:submit, order}, _from, state) do
  total = Enum.sum(...) * if order.user.tier == :premium, do: 0.9, else: 1.0
  ...
end
```

Same rule and same reasoning as the LiveView check: the logic is now reachable only by sending
this process a message, which makes it awkward to test and impossible to reuse. The callback
should call `Orders.submit(order)`.

### 3. Slow or external work inside `handle_call/3` — High

HTTP requests, `Repo` queries against large tables, `System.cmd`, or file I/O in a callback of
a process that other code calls into.

The mailbox is serial: every caller waits, and once the work exceeds the caller's `GenServer.call`
timeout (5s by default) they start crashing while the server keeps working. A single named
GenServer doing an API call per request is a throughput ceiling and an outage vector at once.

Usual fixes: `Task.Supervisor.async_nolink/3` with the result arriving via `handle_info/2`, an
Oban job, or `{:noreply, state, {:continue, ...}}` for post-init work. If the process exists
solely to serialize access to something, say so in the finding and flag only the timeout risk.

**When the slow work has to stay in the process** — it's deliberately synchronous (e.g. for
deterministic tests) or it owns state it must mutate in place — move the *reads* out instead of the
work. Have the process publish its current answers to a store readers hit directly: ETS, or the value
slot of the `Registry` it's already registered in (`Registry.update_value/3`), refreshed on every
state change. Callers that only *read* state then `Registry.lookup`/`:ets.lookup` instead of
`GenServer.call`, so they never queue behind the slow callback. Reach for this when the readers are on
a hot path — a page render, a request guard — that can't afford a 5s wait while the process is busy.
A watcher process that rebuilds a snapshot synchronously is the shape: the rebuild stays in the
process, while readers take its published Registry value, so a rebuild never blocks a page render
or a request guard.

### 4. Unsupervised processes — High

`spawn/1`, `spawn_link/1`, or bare `Task.start/1` in application code.

```elixir
# finding
spawn(fn -> MyApp.Reports.generate(id) end)
```

Nothing restarts it, nothing reports its crash, and it dies silently if its parent dies.
`Task.Supervisor.start_child/2` is the minimum; if the work must actually complete, it's an
Oban job. `Task.async/await` within a request is fine — the caller is waiting and linked.

### 5. `cast` where delivery matters — Medium

`GenServer.cast/2` is fire-and-forget with no backpressure. If the caller needs to know the
work happened, or the mailbox can grow faster than it drains, that's a finding. Casts for
genuine notifications are fine.

### 6. A single named process on a hot path — Medium

One globally named GenServer that every request touches serializes the whole application
through one mailbox. Worth flagging when the process is newly introduced on a request path.
The alternatives — a Registry with per-entity processes, a partitioned pool, or just ETS —
depend on why the process exists, so name them as options rather than prescribing one.

### 7. Missing timeouts and `init/1` work — Low to Medium

`GenServer.call/2` relying on the default 5s timeout for work known to be slower; heavy work
inside `init/1` blocking the supervisor's startup (use `handle_continue/2`).

### 8. A supervised process kept alive by a peer's poll loop, not its supervisor — Medium

A process that runs under a supervisor but whose *(re)start* is driven by some other process calling
`ensure_started` on a timer, instead of by the supervisor's restart strategy plus explicit lifecycle
events. The tell: an unrelated periodic process (a poller, a broadcaster) calls `X.ensure_started(...)`
every tick "to be safe."

```elixir
# in the stats poller's tick — finding
def handle_info(:tick, state) do
  ensure_watchers()   # start a watcher for every live item, every tick
  broadcast(...)
  {:noreply, state}
end
```

This conflates two jobs. Restart-on-crash is the supervisor's (`:transient`/`:permanent` under a
`DynamicSupervisor`), and it already does it. *Initial* start belongs to a real event — app boot, or
the domain action that makes the process necessary — not to whoever happens to tick nearby. Leaning on
the poll loop hides the true lifecycle, resurrects the process on a lag (up to one tick late), and
couples the poller to a concern that isn't its own.

Fixes: give the child the right `restart:` so the supervisor owns liveness; start it from the events
that actually create the need (a boot task over existing state, and the create/publish path); if a
peer genuinely must trigger it, make that explicit and one-directional, not an every-tick safety net.
The shape to move to: "supervised
`:transient`, started at boot and by the domain event that creates the need; the poller only feeds it snapshots."

## Not a finding

- **LiveView processes, Phoenix channels, and Oban workers.** These are processes, but they're
  supervised by the framework and reviewed under their own rules. Don't apply this file to
  `lib/*_web/live/` or the workers directory.
- **Anything under a `Task.Supervisor`, `DynamicSupervisor`, or a supervision tree.** That's the
  correct pattern, not a finding.
- **GenServers owning a connection, pool, or external resource.** Serializing access is often
  exactly the point.
- **ETS-backed caches and rate limiters** whose state is meant to be ephemeral.
- **`Task.async` / `Task.await` inside a request** where the caller waits for the result.
- **`handle_info/2` receiving a PubSub message and updating state.** Plumbing.
- **`Agent` for genuinely small, ephemeral state.** Simplicity is a valid choice; only flag it
  under #1, when the state should have been durable.
- **Test helpers and `test/support/` processes.**

## Judgment calls

Two questions cover most cases. **What happens if this process dies right now?** If the answer
involves lost data, it's #1. If the answer is "it restarts and everything is fine," the process
is probably doing its job.

**Why does this need to be a process at all?** Legitimate answers: it owns state over time, it
serializes access to something, it isolates failure, or it does work concurrently with the
caller. If none of those apply, the code may want to be a plain module — worth raising once,
gently, since rewriting it is a real change and the author may have context the diff doesn't show.

## Overlap with other checks

- HTTP calls inside a callback are finding 3 here; if the project grows an external-services
  reference, report them there instead, since the timeout and adapter fixes are the actionable ones.
- Domain logic in a callback that also queries another context's schema trips
  `context-boundaries.md`. Report under **this** file, since relocating the logic resolves both.
