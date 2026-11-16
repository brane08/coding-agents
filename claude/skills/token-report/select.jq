select(.type == "assistant" and (.message.usage != null))
| select((.message.model // "") != "<synthetic>")
| {f: input_filename, id: (.message.id // .uuid // "x"), m: (.message.model // "unknown"), u: .message.usage}
