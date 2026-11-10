# The Elixir half of the compatibility fixtures: writes elixir/<case>.md, each
# case in cases.json written by this strum, for generate.cr to read with
# Crystal strum. Run by regenerate.sh.
dir = __DIR__
File.mkdir_p!(Path.join(dir, "elixir"))

for c <- dir |> Path.join("cases.json") |> File.read!() |> JSON.decode!() do
  options =
    for {key, value} <- c["options"] do
      value = if is_binary(value), do: String.to_existing_atom(value), else: value
      {String.to_existing_atom(key), value}
    end

  File.write!(
    Path.join([dir, "elixir", c["name"] <> ".md"]),
    Strum.to_markdown(c["sections"], options)
  )
end
