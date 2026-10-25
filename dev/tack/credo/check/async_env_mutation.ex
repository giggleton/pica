defmodule Tack.Credo.Check.AsyncEnvMutation do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      A test file declared `async: true` does not change application config.

      ExUnit's scheduling is an invariant a suite comes to lean on: every `async: true` module
      runs first, then the sync modules run serially — so an async test may safely *read* config
      that only sync files ever mutate.

      Application env is one table for the whole VM, and the database sandbox does not reach it. A
      `put_env` in an async file is therefore visible to every test running beside it for as long
      as the override lasts, and the test that fails is whichever one happened to read the key in
      that window — never the file that set it. `SyncTestBlocker` holds the other half of this rule
      (a sync file says why it is sync); this one holds the half that breaks other files.

      It flags, inside a module whose `use` carries `async: true`, a call to
      `Application.put_env`, `put_all_env` or `delete_env`, or to one of the `TestEnv` helpers
      (`test/support/test_env.ex`: `put_app_env`, `merge_app_env`, `delete_app_env`) — qualified
      or imported, since the helper restores the value afterwards but cannot make the override
      private to its test. The remedy is one of two: pass the value to the code under test as an
      option, or make the file `async: false` and name the key in its header.

      What it cannot see is a mutation one call away: a `test/support` stub that calls
      `Application.put_env` for its caller reads as an ordinary call here. A new async file that
      uses one is a review finding.
      """
    ]

  @application_mutators [:put_env, :put_all_env, :delete_env]
  @helper_mutators [:put_app_env, :merge_app_env, :delete_app_env]

  @message "An `async: true` test file changes application config, which every test running " <>
             "beside it reads. Pass the value as an option, or make the file `async: false` and " <>
             "name the key in its header."

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.Code.prewalk(fn ast, acc -> find_async_module(ast, acc) end)
    |> Enum.map(fn {trigger, line_number} -> issue_for(issue_meta, trigger, line_number) end)
  end

  defp find_async_module({:defmodule, _meta, [_name, [do: body]]} = ast, mutations) do
    if async?(body), do: {ast, mutations(body) ++ mutations}, else: {ast, mutations}
  end

  defp find_async_module(ast, mutations), do: {ast, mutations}

  defp async?(body) do
    {_body, found} =
      Macro.prewalk(body, false, fn
        {:use, _meta, arguments} = ast, found when is_list(arguments) ->
          {ast, found or Enum.any?(arguments, &async_option?/1)}

        ast, found ->
          {ast, found}
      end)

    found
  end

  defp async_option?(argument), do: is_list(argument) and Keyword.get(argument, :async) == true

  defp mutations(body) do
    {_body, found} = Macro.prewalk(body, [], fn ast, found -> {ast, mutation(ast) ++ found} end)
    found
  end

  defp mutation(
         {{:., _dot, [{:__aliases__, _alias, [:Application]}, function]}, meta, _arguments}
       )
       when function in @application_mutators,
       do: [{"Application.#{function}", meta[:line]}]

  defp mutation({{:., _dot, [{:__aliases__, _alias, aliases}, function]}, meta, _arguments})
       when function in @helper_mutators do
    if List.last(aliases) == :TestEnv, do: [{"TestEnv.#{function}", meta[:line]}], else: []
  end

  defp mutation({function, meta, arguments})
       when function in @helper_mutators and is_list(arguments),
       do: [{to_string(function), meta[:line]}]

  defp mutation(_ast), do: []

  defp issue_for(issue_meta, trigger, line_number) do
    format_issue(issue_meta, message: @message, trigger: trigger, line_no: line_number)
  end
end
