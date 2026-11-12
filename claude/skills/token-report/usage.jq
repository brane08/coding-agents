[ inputs
  | select(.type == "assistant" and (.message.usage != null))
  | select((.message.model // "") != "<synthetic>")
  | {f: input_filename, id: (.message.id // .uuid // "x"), m: (.message.model // "unknown"), u: .message.usage}
]
| unique_by(.f + .id)
| group_by(.m)
| map({
    model: .[0].m,
    sessions: (map(.f) | unique | length),
    msgs: length,
    input: (map(.u.input_tokens // 0) | add),
    output: (map(.u.output_tokens // 0) | add),
    cache_read: (map(.u.cache_read_input_tokens // 0) | add),
    cache_create: (map(.u.cache_creation_input_tokens // 0) | add)
  })
| sort_by(-.output) as $rows
| ($rows + [{
    model: "TOTAL",
    sessions: ($rows | map(.sessions) | add // 0),
    msgs: ($rows | map(.msgs) | add // 0),
    input: ($rows | map(.input) | add // 0),
    output: ($rows | map(.output) | add // 0),
    cache_read: ($rows | map(.cache_read) | add // 0),
    cache_create: ($rows | map(.cache_create) | add // 0)
  }])
| .[]
| [.model, .sessions, .msgs, .input, .output, .cache_read, .cache_create,
   (if .msgs > 0 then ((.cache_read / .msgs) | floor) else 0 end)]
| @tsv
