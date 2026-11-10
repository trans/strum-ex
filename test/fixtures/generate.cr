# The Crystal half of the compatibility fixtures: what Crystal strum writes
# and reads, for the Elixir tests to compare against (test/compat_test.exs).
# Run by regenerate.sh, which says what it needs.
#
# It writes, under crystal/:
#   <case>.md                each case in cases.json, written by Crystal strum
#   <case>.json              Crystal's parse of that
#   from-elixir/<case>.json  Crystal's parse of what Elixir wrote (elixir/<case>.md)
#   documents/<doc>.json     Crystal's parse of each of documents/<doc>.md
#   scalars.json             what each line of scalars.txt reads as, as a
#                            YAML value in a block and in braces
require "../../../strum/src/strum"

DIR = __DIR__

# A value as JSON, with the floats JSON can't hold (infinities, NaN) as
# {"nonfinite": "-Infinity"}.
def write_value(json : JSON::Builder, value : JSON::Any)
  case raw = value.raw
  when Float64
    if raw.nan? || raw.infinite?
      json.object { json.field("nonfinite", raw.to_s) }
    else
      json.scalar(raw)
    end
  when Array
    json.array { raw.each { |v| write_value(json, v) } }
  when Hash
    json.object { raw.each { |k, v| json.field(k) { write_value(json, v) } } }
  else
    value.to_json(json)
  end
end

def write_sections(path, sections)
  File.write(path, JSON.build(indent: "  ") { |json|
    json.array { sections.each { |s| write_value(json, JSON::Any.new(s)) } }
  } + "\n")
end

def parse_or_error(markdown)
  Strum.parse(markdown)
rescue ex
  [{"error" => JSON::Any.new("#{ex.class}: #{ex.message}")}]
end

# Sections from JSON, as Crystal strum takes them: a level as an Int32, and
# metadata as a Hash (JSON::Any for either isn't understood).
def sections_from(json : JSON::Any)
  json.as_a.map do |s|
    section = {} of String => JSON::Any | Int32 | Hash(String, JSON::Any)
    s.as_h.each do |key, value|
      section[key] =
        case key
        when "level"    then value.as_i
        when "metadata" then value.as_h
        else                 value
        end
    end
    section
  end
end

def options_from(json : JSON::Any)
  Strum::Options.new(
    metadata_format: json["metadata_format"]?.try(&.as_s) == "json" ? :json : :yaml,
    metadata_style: json["metadata_style"]?.try(&.as_s) == "compact" ? :compact : :multiline,
    quote_strings: json["quote_strings"]?.try(&.as_bool) != false
  )
end

Dir.mkdir_p("#{DIR}/crystal/from-elixir")
Dir.mkdir_p("#{DIR}/crystal/documents")

JSON.parse(File.read("#{DIR}/cases.json")).as_a.each do |c|
  name = c["name"].as_s
  markdown = Strum.to_markdown(sections_from(c["sections"]), options_from(c["options"]))
  File.write("#{DIR}/crystal/#{name}.md", markdown)
  write_sections("#{DIR}/crystal/#{name}.json", parse_or_error(markdown))

  elixir = "#{DIR}/elixir/#{name}.md"
  write_sections("#{DIR}/crystal/from-elixir/#{name}.json", parse_or_error(File.read(elixir))) if File.exists?(elixir)
end

Dir.glob("#{DIR}/documents/*.md").sort.each do |path|
  write_sections("#{DIR}/crystal/documents/#{File.basename(path, ".md")}.json", parse_or_error(File.read(path)))
end

scalars = File.read_lines("#{DIR}/scalars.txt")
File.write("#{DIR}/crystal/scalars.json", JSON.build(indent: "  ") { |json|
  json.array do
    scalars.each do |s|
      json.object do
        json.field("scalar", s)
        {"block" => "## [x] X\n---\nk: #{s}\n---\n", "flow" => "## [x] X\n{k: #{s}}\n"}.each do |context, markdown|
          json.field(context) do
            section = parse_or_error(markdown).first?
            if section && (metadata = section["metadata"]?)
              write_value(json, metadata)
            elsif section && (error = section["error"]?)
              json.object { json.field("error", error.as_s) }
            else
              json.null
            end
          end
        end
      end
    end
  end
} + "\n")
