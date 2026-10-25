defmodule Tack.Credo.Check.CorePurity do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      The pure core takes values as arguments: no clock read, no config read, no process, no IO.

      CLAUDE.md, Approach & architecture: the pure domain rules are a `boundary` declaration with
      `type: :strict`, so a core module reaching a context, a read model or any external library
      fails the build. This check is the part of the core's contract the compiler cannot hold. What
      Boundary cannot see is the standard library: `DateTime.utc_now/0`, `Application.get_env/3`,
      `spawn/1` and `File.read/1` are `:elixir`/`:kernel`, and a core module calling one compiles
      in silence.

      Four categories, each with the shape that replaces it:

        * **Clock reads** — take the instant as an argument. A small `Clock` module at the boundary
          reads the wall clock and hands the value to a pure core fold.
        * **Config reads** — take the value as an argument. Where a question genuinely needs both
          config and a pure fold, it gets its own small module above the core.
        * **Unseeded randomness** — every source of randomness derives from an injected integer
          seed, through the state-passing `:rand` API (`:rand.seed_s/2` with `:rand.uniform_s/1`)
          or `:erlang.phash2/1,2`. The process-dictionary API (`:rand.uniform/0`, `Enum.random/1`)
          is not reproducible, and every run must replay.
        * **Processes and IO** — the core is values in, values out.

      Scope this check to the core in `.credo.exs` with a `files:` filter; it says nothing about
      the rest of the tree, where all four categories are ordinary.
      """
    ]

  # Wall-clock reads. The pure date arithmetic stays in the core; the read of "now" does not.
  @clock_reads [
    {DateTime, :utc_now},
    {DateTime, :now},
    {DateTime, :now!},
    {NaiveDateTime, :utc_now},
    {NaiveDateTime, :local_now},
    {Date, :utc_today},
    {Time, :utc_now},
    {System, :system_time},
    {System, :os_time},
    {System, :monotonic_time},
    {:os, :timestamp},
    {:os, :system_time},
    {:erlang, :system_time},
    {:erlang, :monotonic_time},
    {:calendar, :local_time},
    {:calendar, :universal_time}
  ]

  @config_reads [
    {Application, :get_env},
    {Application, :fetch_env},
    {Application, :fetch_env!},
    {Application, :get_all_env},
    {Application, :compile_env},
    {Application, :compile_env!},
    {Application, :put_env},
    {Application, :put_all_env}
  ]

  # Randomness that reads or writes the process dictionary instead of an injected seed. The
  # state-passing siblings (`:rand.seed_s/2`, `:rand.uniform_s/1`) are the sanctioned form and are
  # deliberately absent.
  @unseeded_randomness [
    {:rand, :seed},
    {:rand, :uniform},
    {:rand, :uniform_real},
    {:rand, :normal},
    {:rand, :bytes},
    {:rand, :jump},
    {Enum, :random},
    {Enum, :shuffle},
    {Enum, :take_random},
    {:crypto, :strong_rand_bytes},
    {:crypto, :rand_uniform},
    {System, :unique_integer},
    {:erlang, :unique_integer}
  ]

  # Modules whose every function is a process, an IO or a mutable-state operation.
  @process_and_io_modules [
    Agent,
    File,
    GenServer,
    IO,
    Node,
    Port,
    Process,
    Registry,
    Supervisor,
    Task,
    :dets,
    :ets,
    :gen_server,
    :persistent_term,
    :timer
  ]

  @process_and_io_functions [
    {System, :cmd},
    {System, :shell},
    {System, :halt}
  ]

  @bare_process_calls [
    {:spawn, 1},
    {:spawn, 3},
    {:spawn_link, 1},
    {:spawn_link, 3},
    {:spawn_monitor, 1},
    {:spawn_monitor, 3},
    {:send, 2}
  ]

  @messages %{
    clock:
      "A core module never reads the clock — take the instant as an argument. A `Clock` module " <>
        "at the boundary is what reads it (CLAUDE.md, Approach & architecture).",
    config:
      "A core module never reads configuration — take the value as an argument, or give the " <>
        "question its own shell above the core (CLAUDE.md, Approach & architecture).",
    randomness:
      "Randomness in the core derives from an injected integer seed: the state-passing `:rand` " <>
        "API (`:rand.seed_s/2` + `:rand.uniform_s/1`) or `:erlang.phash2/1,2`. Every run must " <>
        "replay from its seed (CLAUDE.md, Approach & architecture).",
    process:
      "No processes, no IO, no network in a core module — it takes values and returns values " <>
        "(CLAUDE.md, Approach & architecture)."
  }

  # Keyed by the module's printed name (`"DateTime"`, `":rand"`), so a module named in the source
  # is looked up without ever creating an atom for it.
  @banned_functions Map.new(
                      Enum.map(@clock_reads, fn call -> {call, :clock} end) ++
                        Enum.map(@config_reads, fn call -> {call, :config} end) ++
                        Enum.map(@unseeded_randomness, fn call -> {call, :randomness} end) ++
                        Enum.map(@process_and_io_functions, fn call -> {call, :process} end),
                      fn {{module, function}, category} ->
                        {{inspect(module), function}, category}
                      end
                    )

  @process_and_io_module_names Enum.map(@process_and_io_modules, &inspect/1)

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(source_file, fn ast, issues -> traverse(ast, issues, issue_meta) end)
  end

  # An Erlang module: `:rand.uniform(6)`, `:os.timestamp()`.
  defp traverse({{:., meta, [module, function]}, _call_meta, _args} = ast, issues, issue_meta)
       when is_atom(module) and is_atom(function) do
    {ast, report(issues, issue_meta, inspect(module), function, meta[:line])}
  end

  # An Elixir module: `DateTime.utc_now()`, `Application.get_env(:my_app, :key)`.
  defp traverse(
         {{:., meta, [{:__aliases__, _alias_meta, module_parts}, function]}, _call_meta, _args} =
           ast,
         issues,
         issue_meta
       )
       when is_atom(function) and is_list(module_parts) do
    if Enum.all?(module_parts, fn part -> is_atom(part) end) do
      name = Enum.map_join(module_parts, ".", &Atom.to_string/1)
      {ast, report(issues, issue_meta, name, function, meta[:line])}
    else
      {ast, issues}
    end
  end

  # `receive do … end` — a process construct with no module to name.
  defp traverse({:receive, meta, _clauses} = ast, issues, issue_meta) do
    {ast, [issue_for(issue_meta, :process, "receive", meta[:line]) | issues]}
  end

  # An unqualified `spawn(fun)` or `send(pid, message)`.
  defp traverse({function, meta, args} = ast, issues, issue_meta)
       when is_atom(function) and is_list(args) do
    if {function, length(args)} in @bare_process_calls do
      trigger = "#{function}/#{length(args)}"
      {ast, [issue_for(issue_meta, :process, trigger, meta[:line]) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp report(issues, issue_meta, module_name, function, line_number) do
    trigger = "#{module_name}.#{function}"

    cond do
      category = Map.get(@banned_functions, {module_name, function}) ->
        [issue_for(issue_meta, category, trigger, line_number) | issues]

      module_name in @process_and_io_module_names ->
        [issue_for(issue_meta, :process, trigger, line_number) | issues]

      true ->
        issues
    end
  end

  defp issue_for(issue_meta, category, trigger, line_number) do
    format_issue(
      issue_meta,
      message: "#{trigger} — #{@messages[category]}",
      trigger: trigger,
      line_no: line_number
    )
  end
end
