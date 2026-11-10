defmodule Strum do
  @moduledoc """
  Strum: STRUctured Markdown. Converts between structured data and
  Markdown documents of sections, each with an id, a title, metadata and
  content. An Elixir port of the Crystal strum, reading and writing the
  same files.

  A section is a map with string keys, so it maps straight to JSON:

      %{
        "id" => "auth-design",
        "title" => "Auth Design",
        "level" => 2,
        "metadata" => %{"kind" => "design", "status" => "proposed"},
        "content" => "Authentication system design."
      }

  and is written as

      ## [auth-design] Auth Design
      ---
      kind: "design"
      status: "proposed"
      ---

      Authentication system design.

  Only a heading with an `[id]` starts a section. Anything else up to the
  next one, other headings and fenced code included, is its content.
  Metadata, if any, comes right after the heading: YAML or JSON between
  `---` lines, or on one line in braces (`{kind: design}`,
  `{"kind": "design"}`). Text before the first section is not kept.
  """

  @type section :: %{optional(String.t() | atom) => term}

  @heading ~r/^(#+)\s+\[([^\]]+)\]\s+(.+)$/u
  @fence ~r/^ {0,3}(`{3,}|~{3,})/

  @max_int64 0x7FFF_FFFF_FFFF_FFFF

  ## Parsing

  @doc """
  Parse Markdown into sections, in order. Each has `"id"`, `"title"` and
  `"level"` (1 for `#`, 2 for `##`, ...), and `"metadata"` (a map) and
  `"content"` (a string, trimmed) when it has them.

      iex> Strum.parse("## [a] Title\\n{kind: note}\\n\\nBody.")
      [%{"id" => "a", "title" => "Title", "level" => 2, "metadata" => %{"kind" => "note"}, "content" => "Body."}]
  """
  @spec parse(String.t()) :: [section]
  def parse(markdown) when is_binary(markdown) do
    lines =
      markdown
      |> String.split("\n")
      |> Enum.map(&String.trim_trailing/1)
      |> List.to_tuple()

    sections(lines, next_heading(lines, 0), [])
  end

  defp sections(lines, i, acc) when i >= tuple_size(lines), do: Enum.reverse(acc)

  defp sections(lines, i, acc) do
    [_, hashes, id, title] = Regex.run(@heading, elem(lines, i))
    {metadata, consumed} = metadata_block(lines, i + 1)
    start = i + 1 + consumed
    stop = next_heading(lines, start)
    content = lines |> join(start, stop - 1) |> String.trim()

    section =
      %{"id" => String.trim(id), "title" => String.trim(title), "level" => byte_size(hashes)}
      |> put_present("metadata", metadata)
      |> put_present("content", if(content == "", do: nil, else: content))

    sections(lines, stop, [section | acc])
  end

  # Lines `first` to `last`, joined.
  defp join(lines, first, last), do: first..last//1 |> Enum.map_join("\n", &elem(lines, &1))

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  # The index of the next section heading at or after `i` (or the number of
  # lines, if there is none), passing over fenced code, where a line like
  # one would be code.
  defp next_heading(lines, i, fence \\ nil)

  defp next_heading(lines, i, _fence) when i >= tuple_size(lines), do: i

  defp next_heading(lines, i, nil) do
    line = elem(lines, i)

    cond do
      fence = fence(line) -> next_heading(lines, i + 1, fence)
      Regex.match?(@heading, line) -> i
      true -> next_heading(lines, i + 1, nil)
    end
  end

  # Inside a fence: it closes with the same character, at least as many of
  # them, and nothing else on the line.
  defp next_heading(lines, i, open) do
    line = elem(lines, i)
    close = fence(line)

    closed? =
      close != nil and binary_part(close, 0, 1) == binary_part(open, 0, 1) and
        byte_size(close) >= byte_size(open) and String.trim(line) == close

    next_heading(lines, i + 1, if(closed?, do: nil, else: open))
  end

  defp fence(line) do
    case Regex.run(@fence, line) do
      [_, fence] -> fence
      nil -> nil
    end
  end

  # Metadata starting at line `i`: `{metadata, lines it takes}`.
  defp metadata_block(lines, i) when i >= tuple_size(lines), do: {nil, 0}

  defp metadata_block(lines, i) do
    first = String.trim(elem(lines, i))

    cond do
      first == "---" ->
        delimited_metadata(lines, i)

      # One line in braces; a first line of content like `Note: text`
      # would read as YAML too
      String.starts_with?(first, "{") ->
        case read_metadata(first) do
          nil -> {nil, 0}
          metadata -> {metadata, 1}
        end

      true ->
        {nil, 0}
    end
  end

  defp delimited_metadata(lines, start) do
    close =
      Enum.find((start + 1)..(tuple_size(lines) - 1)//1, &(String.trim(elem(lines, &1)) == "---"))

    if close do
      text = lines |> join(start + 1, close - 1) |> String.trim()

      case {read_metadata(text), text} do
        # nothing between the lines: metadata, but none
        {nil, ""} -> {nil, close - start + 1}
        # not a mapping, so not metadata: content between two rules, say
        {nil, _} -> {nil, 0}
        {metadata, _} -> {metadata, close - start + 1}
      end
    else
      {nil, 0}
    end
  end

  # JSON if it looks like it and is an object, otherwise YAML if it's a
  # mapping with string keys; nil if neither.
  defp read_metadata(""), do: nil

  defp read_metadata(text) do
    json =
      if String.starts_with?(text, ["{", "["]) do
        # Crystal's Hash: a later key replaces an earlier one
        last_wins = fn pairs, acc -> {pairs |> Enum.reverse() |> Map.new(), acc} end

        case JSON.decode(text, nil, object_finish: last_wins) do
          {%{} = map, _, rest} -> if String.trim(rest) == "" and int64s?(map), do: map
          _ -> nil
        end
      end

    json ||
      case Strum.YAML.read(text) do
        {:ok, map} -> map
        :error -> nil
      end
  end

  # Crystal's JSON has no integers beyond 64 bits: such JSON is read as YAML.
  defp int64s?(n) when is_integer(n), do: n >= -@max_int64 - 1 and n <= @max_int64
  defp int64s?(map) when is_map(map), do: Enum.all?(map, fn {_, v} -> int64s?(v) end)
  defp int64s?(list) when is_list(list), do: Enum.all?(list, &int64s?/1)
  defp int64s?(_), do: true

  ## Writing

  @doc """
  Write sections as Markdown, separated by blank lines. A section needs an
  `"id"` and a `"title"`; `"level"` is 2 unless given. Atom keys (`:id`)
  work too. Metadata may be a map, written in key order, or a list of
  `{key, value}` pairs, written in that order, at any depth.

  Options:

    * `:metadata_format`: `:yaml` (the default) or `:json`
    * `:metadata_style`: `:multiline` (the default), between `---` lines,
      or `:compact`, on one line in braces
    * `:quote_strings`: whether YAML strings are quoted (default `true`).
      When `false`, a string is still quoted if, written plain, it would
      read as something else (`yes`, `12`, `a: b`).
  """
  @spec to_markdown([section], keyword) :: String.t()
  def to_markdown(sections, options \\ []) when is_list(sections) do
    options =
      Keyword.validate!(options,
        metadata_format: :yaml,
        metadata_style: :multiline,
        quote_strings: true
      )

    Enum.map_join(sections, "\n\n", &render_section(&1, options))
  end

  defp render_section(section, options) do
    id = get(section, "id", :id, "")
    title = get(section, "title", :title, "")
    level = get(section, "level", :level, 2)
    metadata = get(section, "metadata", :metadata, nil)
    content = get(section, "content", :content, nil)

    unless is_integer(level) and level > 0 do
      raise ArgumentError, "a section's level must be a positive integer, got #{inspect(level)}"
    end

    heading = "#{String.duplicate("#", level)} [#{text(id)}] #{text(title)}"
    metadata = if metadata, do: render_metadata(metadata, options), else: ""
    content = if content, do: content |> text() |> String.trim(), else: ""

    [heading]
    |> Kernel.++(if metadata == "", do: [], else: [metadata])
    |> Kernel.++(if content == "", do: [], else: ["", content])
    |> Enum.join("\n")
  end

  defp get(section, key, atom, default),
    do: Map.get(section, key) || Map.get(section, atom) || default

  defp text(value) when is_binary(value), do: value
  defp text(value) when is_float(value), do: float_text(value)
  defp text(value), do: to_string(value)

  defp render_metadata(metadata, options) do
    case pairs(metadata) do
      nil ->
        ""

      pairs ->
        case {options[:metadata_format], options[:metadata_style]} do
          {:json, :multiline} ->
            "---\n#{json(metadata, "")}\n---"

          {:json, _} ->
            json(metadata)

          {_yaml, :multiline} ->
            Enum.join(["---"] ++ Enum.map(pairs, &yaml_line(&1, options, false)) ++ ["---"], "\n")

          {_yaml, _} ->
            "{" <> Enum.map_join(pairs, ", ", &yaml_line(&1, options, true)) <> "}"
        end
    end
  end

  # A mapping's entries, in the order they're written: a map's by key, a
  # list of pairs' as listed. nil if it isn't a mapping.
  defp pairs(%{} = map),
    do: map |> Enum.map(fn {k, v} -> {text(k), v} end) |> Enum.sort_by(&elem(&1, 0))

  defp pairs([_ | _] = list) do
    if Enum.all?(list, &match?({k, _} when is_binary(k) or is_atom(k), &1)),
      do: Enum.map(list, fn {k, v} -> {text(k), v} end)
  end

  defp pairs(_), do: nil

  defp yaml_line({key, value}, options, flow),
    do: "#{Strum.YAML.string(key, false, flow)}: #{yaml(value, options, flow)}"

  defp yaml(value, options, flow) do
    case pairs(value) do
      nil when is_binary(value) ->
        Strum.YAML.string(value, options[:quote_strings], flow)

      nil when is_list(value) ->
        "[" <> Enum.map_join(value, ", ", &yaml(&1, options, true)) <> "]"

      nil ->
        scalar(value)

      pairs ->
        "{" <> Enum.map_join(pairs, ", ", &yaml_line(&1, options, true)) <> "}"
    end
  end

  # JSON as Crystal's builder writes it: compact, or indented by two spaces
  # with every element on a line of its own.
  defp json(value) do
    case pairs(value) do
      nil when is_list(value) ->
        "[" <> Enum.map_join(value, ",", &json/1) <> "]"

      nil ->
        json_scalar(value)

      pairs ->
        "{" <>
          Enum.map_join(pairs, ",", fn {k, v} -> Strum.YAML.json_string(k) <> ":" <> json(v) end) <>
          "}"
    end
  end

  defp json(value, indent) do
    inner = indent <> "  "

    case pairs(value) do
      nil when value == [] ->
        "[]"

      nil when is_list(value) ->
        "[\n" <> Enum.map_join(value, ",\n", &(inner <> json(&1, inner))) <> "\n" <> indent <> "]"

      nil ->
        json_scalar(value)

      [] ->
        "{}"

      pairs ->
        entries =
          Enum.map_join(pairs, ",\n", fn {k, v} ->
            "#{inner}#{Strum.YAML.json_string(k)}: #{json(v, inner)}"
          end)

        "{\n" <> entries <> "\n" <> indent <> "}"
    end
  end

  defp json_scalar(value) when is_binary(value), do: Strum.YAML.json_string(value)

  defp json_scalar(value) when is_atom(value) and value not in [nil, true, false],
    do: Strum.YAML.json_string(Atom.to_string(value))

  defp json_scalar(value), do: scalar(value)

  defp scalar(nil), do: "null"
  defp scalar(true), do: "true"
  defp scalar(false), do: "false"
  defp scalar(n) when is_integer(n), do: Integer.to_string(n)
  defp scalar(f) when is_float(f), do: float_text(f)
  defp scalar(a) when is_atom(a), do: Atom.to_string(a)
  defp scalar(other), do: raise(ArgumentError, "can't write #{inspect(other)} in metadata")

  @doc false
  # A float as Crystal's `Float64#to_s` writes it: the shortest digits that
  # read back as it, in decimal notation from 1.0e-4 up to 1.0e+15, and
  # otherwise in scientific notation with a signed exponent (`1.0e+20`).
  def float_text(f) do
    {sign, short} =
      case :erlang.float_to_binary(f, [:short]) do
        "-" <> short -> {"-", short}
        short -> {"", short}
      end

    {mantissa, exp} =
      case String.split(short, "e") do
        [m, e] -> {m, String.to_integer(e)}
        [m] -> {m, 0}
      end

    [int | frac] = String.split(mantissa, ".")
    digits = int <> Enum.join(frac)
    stripped = String.trim_leading(digits, "0")
    # digits before the decimal point
    point = byte_size(int) + exp - (byte_size(digits) - byte_size(stripped))
    digits = String.trim_trailing(stripped, "0")
    size = byte_size(digits)
    x = point - 1

    cond do
      digits == "" ->
        sign <> "0.0"

      x < -4 or x >= 15 ->
        rest = if size > 1, do: binary_part(digits, 1, size - 1), else: "0"
        "#{sign}#{binary_part(digits, 0, 1)}.#{rest}e#{if x >= 0, do: "+", else: "-"}#{abs(x)}"

      point <= 0 ->
        sign <> "0." <> String.duplicate("0", -point) <> digits

      point >= size ->
        sign <> digits <> String.duplicate("0", point - size) <> ".0"

      true ->
        sign <> binary_part(digits, 0, point) <> "." <> binary_part(digits, point, size - point)
    end
  end
end
