## [numbers] Numbers
{"int": 1, "neg": -2, "float": 2.5, "exp": 1e3, "big": 12345678901234567890, "zero": -0, "fzero": -0.0}

## [nested] Nested
---
{
  "a": {"b": {"c": [1, 2, {"d": null}]}},
  "t": true,
  "s": "line\nbreak \u00e9"
}
---

## [dupes] Duplicate Keys
{"k": 1, "k": 2}

## [fallback] Not JSON, Read as YAML
{kind: yaml, "quoted": yes}

## [array] An Array Isn't Metadata
---
[1, 2, 3]
---

Content.
