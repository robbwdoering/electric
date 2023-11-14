// tagged template literal dedent function
export function dedent(
  strings: TemplateStringsArray,
  ...values: unknown[]
): string {
  let str = strings[0]
  for (let i = 0; i < values.length; i++) {
    str += String(values[i]) + strings[i + 1]
  }

  const lines = str.split('\n')

  const minIndent = lines
    .filter((line) => line.trim())
    .reduce((minIndent, line) => {
      const indent = line.match(/^\s*/)![0].length
      return indent < minIndent ? indent : minIndent
    }, Infinity)

  if (lines[0] === '') {
    // if first line is empty, remove it
    lines.shift()
  }
  if (lines[lines.length - 1] === '') {
    // if last line is empty, remove it
    lines.pop()
  }

  return lines
    .map((line) => {
      line = line.slice(minIndent)
      if (/^\s/.test(line)) {
        // if line starts with whitespace, prefix it with a newline
        // to preserve the indentation
        return '\n' + line
      } else if (line === '') {
        // if line is empty, we want a newline here
        return '\n'
      } else {
        return line.trim() + ' '
      }
    })
    .join('')
    .trim()
}
