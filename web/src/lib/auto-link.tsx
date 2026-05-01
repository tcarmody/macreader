import type { ReactNode } from 'react'

const URL_REGEX = /https?:\/\/\S+/g
// Trim trailing punctuation that's almost always part of the surrounding sentence,
// not the URL itself (e.g. "see http://example.com.")
const TRAILING_PUNCT = /[.,!?;:)\]]+$/

/**
 * Render a plain text string with bare URLs converted to clickable anchors.
 * Returns an array of strings and <a> elements suitable for inline rendering.
 */
export function autoLinkText(text: string): ReactNode[] {
  const out: ReactNode[] = []
  let last = 0
  const re = new RegExp(URL_REGEX)
  let match: RegExpExecArray | null

  while ((match = re.exec(text)) !== null) {
    const raw = match[0]
    const trailing = raw.match(TRAILING_PUNCT)?.[0] ?? ''
    const url = trailing ? raw.slice(0, -trailing.length) : raw
    const start = match.index
    if (start > last) out.push(text.slice(last, start))
    out.push(
      <a
        key={`${start}-${url}`}
        href={url}
        target="_blank"
        rel="noopener noreferrer"
        className="underline decoration-dotted underline-offset-2 hover:decoration-solid"
        onClick={(e) => e.stopPropagation()}
      >
        {url}
      </a>
    )
    if (trailing) out.push(trailing)
    last = start + raw.length
  }
  if (last < text.length) out.push(text.slice(last))
  return out
}
