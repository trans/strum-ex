defmodule Strum.YAML do
  @moduledoc false

  # YAML for section metadata, read and written as Crystal strum does, so
  # that a file means the same to both. yamerl does the parsing, but plain
  # scalars (and those tagged bool, int, float, null or timestamp) are
  # resolved by the rules of Crystal's YAML core schema
  # (`YAML::Schema::Core.parse_scalar`), which differ from yamerl's own:
  # `yes`, `on` and `off` are booleans, `017` is octal, `1_000` is an
  # integer, and a date is a time, kept as the text Crystal's `Time#to_s`
  # gives it (`2026-11-09 00:00:00 UTC`).
  #
  # Two things Crystal reads can't be held here: an infinite or NaN float
  # (`-inf`, `+nan`, `-Infinity`) is kept as the text it was written as,
  # and a binary (`!!binary`) isn't supported.

  @nulls ["", "~", "null", "Null", "NULL"]
  @trues ["yes", "Yes", "YES", "true", "True", "TRUE", "on", "On", "ON"]
  @falses ["no", "No", "NO", "false", "False", "FALSE", "off", "Off", "OFF"]
  @infinities_and_nans ~w(.inf .Inf .INF +.inf +.Inf +.INF -.inf -.Inf -.INF .nan .NaN .NAN)

  @max_uint64 0xFFFF_FFFF_FFFF_FFFF
  @max_int64 0x7FFF_FFFF_FFFF_FFFF

  @doc """
  Read YAML that should be a mapping with string keys, as Crystal strum
  does: `{:ok, map}`, or `:error` if it doesn't parse, isn't a mapping, or
  has a key (at any depth) that isn't a string.
  """
  def read(text) do
    options = [
      schema: :failsafe,
      node_mods: [Strum.YAML.Scalars],
      detailed_constr: true,
      str_node_as_binary: true,
      keep_duplicate_keys: true
    ]

    case :yamerl_constr.string(text, options) do
      [{:yamerl_doc, {:yamerl_map, _, _, _, _} = root} | _] -> {:ok, value(root)}
      _ -> :error
    end
  catch
    # yamerl throws its parse errors, and the above throws what Crystal
    # would raise for
    :throw, _ -> :error
  end

  defp value({:strum_scalar, _, _, _, value}), do: value
  defp value({:yamerl_str, _, _, _, text}), do: to_string(text)
  defp value({:yamerl_seq, _, _, _, entries, _count}), do: Enum.map(entries, &value/1)

  defp value({:yamerl_map, _, _, _, pairs}) do
    # Crystal's Hash: a later key replaces an earlier one
    pairs
    |> entries()
    |> Enum.reduce(%{}, fn {key, val}, map ->
      case value(key) do
        key when is_binary(key) -> Map.put(map, key, value(val))
        _ -> throw(:key_not_a_string)
      end
    end)
  end

  defp value(node), do: throw({:unsupported, node})

  # A mapping's pairs in the order Crystal takes them, with merges (`<<`)
  # expanded where they stand: a merged mapping's pairs, and of a sequence
  # of mappings, the last one's first (so earlier ones win).
  defp entries(pairs) do
    Enum.flat_map(pairs, fn {key, val} = pair ->
      if merge?(key) do
        case val do
          {:yamerl_map, _, _, _, merged} ->
            entries(merged)

          {:yamerl_seq, _, _, _, items, _} ->
            if Enum.all?(items, &match?({:yamerl_map, _, _, _, _}, &1)),
              do: items |> Enum.reverse() |> Enum.flat_map(&entries(elem(&1, 4))),
              else: [pair]

          _ ->
            [pair]
        end
      else
        [pair]
      end
    end)
  end

  defp merge?(key), do: match?({_, _, _, _, _}, key) and value(key) == "<<"

  ## Scalars

  @doc "A plain scalar, resolved as Crystal's `YAML::Schema::Core.parse_scalar` does."
  def scalar(s) do
    cond do
      s in @nulls -> nil
      s in @trues -> true
      s in @falses -> false
      s in @infinities_and_nans -> s
      String.starts_with?(s, ["0x", "+0x", "-0x"]) -> int(s, 16, false, true, false) || s
      String.starts_with?(s, ["0.", "."]) -> float(s) || s
      s == "0" -> 0
      String.starts_with?(s, "0") -> int(s, 8, false, true, true) || s
      String.starts_with?(s, ["-", "+"]) -> number(s) || s
      digit?(s) -> number(s) || time(s) || s
      true -> s
    end
  end

  @doc """
  A scalar explicitly tagged, as Crystal reads it; throws if the text isn't
  of the tag's kind, which Crystal treats as the YAML not parsing.
  """
  def tagged(kind, s) do
    value =
      case kind do
        :null -> if s in @nulls, do: {:ok, nil}
        :bool -> if s in @trues, do: {:ok, true}, else: if(s in @falses, do: {:ok, false})
        :int -> if s == "0", do: {:ok, 0}, else: ok(int(s, 10, true, true, true))
        :float -> if s in @infinities_and_nans, do: {:ok, s}, else: ok(float(s))
        :timestamp -> ok(time(s))
      end

    case value do
      {:ok, value} -> value
      nil -> throw({:invalid, kind, s})
    end
  end

  defp ok(nil), do: nil
  defp ok(value), do: {:ok, value}

  defp digit?(<<c, _::binary>>), do: c in ?0..?9
  defp digit?(_), do: false

  defp number(s), do: int(s, 10, true, false, true) || float(s)

  # Crystal's `String#to_i64?` with these options (whitespace and strict on).
  defp int(s, base, underscore, prefix, octal) do
    {negative, rest} =
      case s do
        "-" <> rest -> {true, rest}
        "+" <> rest -> {false, rest}
        rest -> {false, rest}
      end

    {base, rest, found, last_underscore} =
      case rest do
        "0" <> after_zero ->
          case after_zero do
            <<c, more::binary>> when prefix and c in ~c"bB" -> {2, more, false, false}
            <<c, more::binary>> when prefix and c in ~c"xX" -> {16, more, false, false}
            <<c, more::binary>> when prefix and c in ~c"oO" -> {8, more, false, false}
            _ when octal -> {8, after_zero, false, false}
            _ when prefix -> {10, after_zero, true, false}
            _ -> {base, after_zero, true, false}
          end

        _ ->
          {base, rest, false, true}
      end

    with {:ok, n} <- digits(rest, base, underscore, 0, found, last_underscore) do
      cond do
        negative and n <= @max_int64 + 1 -> -n
        not negative and n <= @max_int64 -> n
        true -> nil
      end
    end
  end

  defp digits("_" <> rest, base, true, n, found, false),
    do: digits(rest, base, true, n, found, true)

  defp digits(<<c, rest::binary>>, base, underscore, n, _found, _last_underscore) do
    d = digit_value(c)

    if d != nil and d < base and n * base + d <= @max_uint64,
      do: digits(rest, base, underscore, n * base + d, true, false),
      else: nil
  end

  defp digits("", _base, _underscore, n, true, _), do: {:ok, n}
  defp digits("", _base, _underscore, _n, false, _), do: nil

  defp digit_value(c) when c in ?0..?9, do: c - ?0
  defp digit_value(c) when c in ?a..?z, do: c - ?a + 10
  defp digit_value(c) when c in ?A..?Z, do: c - ?A + 10
  defp digit_value(_), do: nil

  @float ~r/^([+-]?)([0-9]*)(?:\.([0-9]*))?(?:[eE]([+-]?[0-9]+))?$/
  @infinity_or_nan ~r/^[+-]?(?:nan(?:\([A-Za-z0-9_]*\))?|inf(?:inity)?)$/i

  # Crystal's `parse_float?`: underscores dropped, then `String#to_f64?`
  # (its port of fast_float). Out of range either way, it's not a float.
  defp float(original) do
    s = String.replace(original, "_", "")

    case Regex.run(@float, s) do
      [_ | groups] ->
        [sign, int, frac, exp] = groups ++ List.duplicate("", 4 - length(groups))
        mantissa = int <> frac

        if mantissa == "" do
          nil
        else
          text = "#{sign}#{zero(int)}.#{zero(frac)}e#{zero(exp)}"

          # an underflow is out of range too
          case to_float(text) do
            f when f == 0.0 -> if String.trim(mantissa, "0") == "", do: f
            f -> f
          end
        end

      nil ->
        if Regex.match?(@infinity_or_nan, s), do: original
    end
  end

  defp zero(""), do: "0"
  defp zero(digits), do: digits

  defp to_float(text) do
    :erlang.binary_to_float(text)
  rescue
    ArgumentError -> nil
  end

  @time ~r/^(\d{1,4})-(\d{1,2})-(\d{1,2})(?:(?:[Tt]|[ \t]+)(\d{1,2}):(\d{1,2}):(\d{1,2})(?:\.(\d{1,9}))?[ \t]*(?:([Zz])|([+-])(\d{1,2}):?(?:(\d{1,2})(?::(\d\d))?)?)?)?$/

  # Crystal's `Time::Format::YAML_DATE.parse?`, then `Time#to_s`: a time
  # with no zone is UTC; fractions of a second are dropped from the text.
  defp time(s) do
    with true <- String.length(s) >= 8,
         [_ | groups] <- Regex.run(@time, s) do
      [year, month, day, hour, minute, second, _fraction, z, sign, oh, om, os] =
        groups ++ List.duplicate("", 12 - length(groups))

      [year, month, day, hour, minute, second] =
        Enum.map([year, month, day, hour, minute, second], &number_or_zero/1)

      with true <- year >= 1,
           {:ok, date} <- Date.new(year, month, day),
           {:ok, time} <- Time.new(hour, minute, second) do
        stamp = "#{Date.to_iso8601(date)} #{Time.to_iso8601(time)}"

        cond do
          sign == "" or z != "" ->
            stamp <> " UTC"

          true ->
            offset = number_or_zero(oh) * 3600 + number_or_zero(om) * 60 + number_or_zero(os)
            stamp <> " " <> zone(if(sign == "-", do: -offset, else: offset))
        end
      else
        _ -> nil
      end
    else
      _ -> nil
    end
  end

  defp number_or_zero(""), do: 0
  defp number_or_zero(digits), do: String.to_integer(digits)

  # Crystal's `Time::Location::Zone#format`: seconds only when there are any.
  defp zone(offset) do
    sign = if offset < 0, do: "-", else: "+"
    offset = abs(offset)
    {h, m, s} = {div(offset, 3600), div(rem(offset, 3600), 60), rem(offset, 60)}
    hm = "#{sign}#{pad(h)}:#{pad(m)}"
    if s == 0, do: hm, else: "#{hm}:#{pad(s)}"
  end

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  ## Writing

  @doc """
  A string as YAML: quoted when asked, or when written plain it wouldn't
  read back as the same string, by Crystal or by this module. Quoted, it is
  a JSON string, which YAML reads too. `flow` is true inside braces or
  brackets.
  """
  def string(str, quote, flow) do
    if quote or not plain?(str, flow), do: json_string(str), else: str
  end

  @doc """
  A string as JSON, escaped as Crystal's JSON writes it: quotes,
  backslashes and control characters (DEL included, which YAML won't take
  raw), the rest as it is.
  """
  def json_string(str) do
    unless String.valid?(str), do: raise(ArgumentError, "not UTF-8: #{inspect(str)}")

    escaped =
      for <<c::utf8 <- str>>, into: "" do
        case c do
          ?" ->
            ~S(\")

          ?\\ ->
            ~S(\\)

          ?\b ->
            ~S(\b)

          ?\f ->
            ~S(\f)

          ?\n ->
            ~S(\n)

          ?\r ->
            ~S(\r)

          ?\t ->
            ~S(\t)

          c when c < 0x20 or c == 0x7F ->
            "\\u" <>
              (c |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(4, "0"))

          c ->
            <<c::utf8>>
        end
      end

    ~S(") <> escaped <> ~S(")
  end

  # Conservative: anything YAML might read as other than this string, in
  # block or flow context, by YAML 1.1 or 1.2 rules, is quoted.
  defp plain?(str, flow) do
    str != "" and str == String.trim(str) and
      not String.match?(str, ~r/[\x00-\x1f\x7f\x{85}\x{2028}\x{2029}\x{feff}]/u) and
      not String.starts_with?(str, ~w(- ? : , [ ] { } # & * ! | > ' " % @ ` = < ...)) and
      not String.contains?(str, [": ", " #"]) and
      not String.ends_with?(str, ":") and
      not (flow and String.contains?(str, [",", "[", "]", "{", "}", ":"])) and
      not reserved?(str) and
      scalar(str) == str and
      reads_back?(str, flow)
  end

  # Strings some YAML reader takes for something else: YAML 1.1's booleans
  # and nulls in any case, anything that starts like a number or a date,
  # and infinities and NaN (`.inf`, and Crystal's `-inf`, `+nan`).
  defp reserved?(str) do
    String.downcase(str) in ~w(y n yes no true false on off null ~) or
      String.match?(str, ~r/^[-+]?\.?[0-9]/) or
      String.match?(str, ~r/^[-+]?\.(inf|nan)$/i) or
      String.match?(str, ~r/^[-+](inf|nan)/i)
  end

  defp reads_back?(str, flow) do
    text = if flow, do: "{k: #{str}}", else: "k: #{str}"
    read(text) == {:ok, %{"k" => str}}
  end
end

defmodule Strum.YAML.Scalars do
  @moduledoc false

  # A yamerl node module: it resolves plain scalars, and those tagged bool,
  # int, float, null or timestamp, by Crystal's rules (`Strum.YAML.scalar/1`
  # and `Strum.YAML.tagged/2`). Quoted scalars are left to yamerl, as
  # strings.

  require Record

  Record.defrecordp(
    :scalar,
    :yamerl_scalar,
    Record.extract(:yamerl_scalar, from_lib: "yamerl/include/yamerl_tokens.hrl")
  )

  Record.defrecordp(
    :tag,
    :yamerl_tag,
    Record.extract(:yamerl_tag, from_lib: "yamerl/include/yamerl_tokens.hrl")
  )

  @tags %{
    ~c"tag:yaml.org,2002:bool" => :bool,
    ~c"tag:yaml.org,2002:int" => :int,
    ~c"tag:yaml.org,2002:float" => :float,
    ~c"tag:yaml.org,2002:null" => :null,
    ~c"tag:yaml.org,2002:timestamp" => :timestamp
  }

  def tags, do: Map.keys(@tags)

  def try_construct_token(constr, node, scalar(tag: tag(uri: {:non_specific, ~c"?"})) = token),
    do: construct_token(constr, node, token)

  def try_construct_token(_constr, _node, _token), do: :unrecognized

  def construct_token(_constr, :undefined, scalar(tag: tag(uri: uri), text: text) = token) do
    text = List.to_string(text)

    value =
      case uri do
        {:non_specific, _} -> Strum.YAML.scalar(text)
        uri -> Strum.YAML.tagged(Map.fetch!(@tags, uri), text)
      end

    {:finished, {:strum_scalar, __MODULE__, uri, :yamerl_constr.get_pres_details(token), value}}
  end

  def node_pres(node), do: elem(node, 3)
end
