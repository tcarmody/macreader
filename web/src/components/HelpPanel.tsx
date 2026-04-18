import { useState, useMemo } from 'react'
import { X, Search, ChevronRight, BookOpen, Wrench, HelpCircle, Rocket } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { ScrollArea } from '@/components/ui/scroll-area'
import { HELP_ARTICLES, HELP_CATEGORIES } from '@/lib/help-content'
import type { HelpArticle } from '@/lib/help-content'

interface HelpPanelProps {
  isOpen: boolean
  onClose: () => void
}

const CATEGORY_ICONS = {
  'getting-started': Rocket,
  'features': BookOpen,
  'troubleshooting': Wrench,
  'faq': HelpCircle,
}

function fuzzyMatch(text: string, query: string): boolean {
  const t = text.toLowerCase()
  const q = query.toLowerCase().trim()
  if (!q) return true
  return q.split(/\s+/).every((word) => t.includes(word))
}

// Minimal markdown → JSX renderer for the help content format
function renderMarkdown(md: string) {
  const lines = md.split('\n')
  const nodes: JSX.Element[] = []
  let i = 0

  const inlineFormat = (text: string, key: string): JSX.Element => {
    // Handle inline code and bold
    const parts = text.split(/(`[^`]+`|\*\*[^*]+\*\*)/)
    return (
      <span key={key}>
        {parts.map((p, pi) => {
          if (p.startsWith('`') && p.endsWith('`'))
            return <code key={pi} className="px-1 py-0.5 bg-muted rounded text-[11px] font-mono">{p.slice(1, -1)}</code>
          if (p.startsWith('**') && p.endsWith('**'))
            return <strong key={pi}>{p.slice(2, -2)}</strong>
          return p
        })}
      </span>
    )
  }

  while (i < lines.length) {
    const line = lines[i]

    // Code fence
    if (line.startsWith('```')) {
      const codeLines: string[] = []
      i++
      while (i < lines.length && !lines[i].startsWith('```')) {
        codeLines.push(lines[i])
        i++
      }
      nodes.push(
        <pre key={i} className="my-2 p-3 bg-muted rounded-md text-[11px] font-mono overflow-x-auto whitespace-pre-wrap">
          {codeLines.join('\n')}
        </pre>
      )
      i++
      continue
    }

    // Table
    if (line.startsWith('|')) {
      const tableLines: string[] = []
      while (i < lines.length && lines[i].startsWith('|')) {
        tableLines.push(lines[i])
        i++
      }
      const rows = tableLines
        .filter((l) => !l.match(/^\|[-| ]+\|$/))
        .map((l) => l.split('|').filter((_, ci) => ci > 0 && ci < l.split('|').length - 1).map((c) => c.trim()))
      nodes.push(
        <table key={i} className="my-2 w-full text-xs border-collapse">
          <thead>
            <tr>
              {rows[0]?.map((cell, ci) => (
                <th key={ci} className="border border-border px-2 py-1 text-left font-semibold bg-muted">{cell}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.slice(1).map((row, ri) => (
              <tr key={ri}>
                {row.map((cell, ci) => (
                  <td key={ci} className="border border-border px-2 py-1">{inlineFormat(cell, `${ri}-${ci}`)}</td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      )
      continue
    }

    // Heading
    if (line.startsWith('## ')) {
      nodes.push(<h2 key={i} className="font-semibold text-sm mt-3 mb-1">{line.slice(3)}</h2>)
      i++; continue
    }
    if (line.startsWith('# ')) {
      nodes.push(<h1 key={i} className="font-bold text-base mt-3 mb-1">{line.slice(2)}</h1>)
      i++; continue
    }

    // Unordered list
    if (line.startsWith('- ')) {
      const items: string[] = []
      while (i < lines.length && lines[i].startsWith('- ')) {
        items.push(lines[i].slice(2))
        i++
      }
      nodes.push(
        <ul key={i} className="my-1 ml-4 space-y-0.5 list-disc text-xs">
          {items.map((item, ii) => <li key={ii}>{inlineFormat(item, String(ii))}</li>)}
        </ul>
      )
      continue
    }

    // Numbered list
    if (/^\d+\. /.test(line)) {
      const items: string[] = []
      while (i < lines.length && /^\d+\. /.test(lines[i])) {
        items.push(lines[i].replace(/^\d+\. /, ''))
        i++
      }
      nodes.push(
        <ol key={i} className="my-1 ml-4 space-y-0.5 list-decimal text-xs">
          {items.map((item, ii) => <li key={ii}>{inlineFormat(item, String(ii))}</li>)}
        </ol>
      )
      continue
    }

    // Blank line
    if (line.trim() === '') {
      i++; continue
    }

    // Normal paragraph
    nodes.push(<p key={i} className="text-xs text-muted-foreground leading-relaxed mb-1">{inlineFormat(line, String(i))}</p>)
    i++
  }

  return nodes
}

function ArticleView({ article, onBack }: { article: HelpArticle; onBack: () => void }) {
  const CategoryIcon = CATEGORY_ICONS[article.category]
  return (
    <div className="flex flex-col h-full">
      <div className="flex items-center gap-2 p-4 border-b border-border">
        <button onClick={onBack} className="text-muted-foreground hover:text-foreground">
          <ChevronRight className="h-4 w-4 rotate-180" />
        </button>
        <CategoryIcon className="h-3.5 w-3.5 text-muted-foreground" />
        <span className="text-xs text-muted-foreground">{HELP_CATEGORIES[article.category]}</span>
      </div>
      <ScrollArea className="flex-1">
        <div className="p-4">
          <h1 className="font-bold text-base mb-3">{article.title}</h1>
          <div>{renderMarkdown(article.body)}</div>
        </div>
      </ScrollArea>
    </div>
  )
}

export function HelpPanel({ isOpen, onClose }: HelpPanelProps) {
  const [query, setQuery] = useState('')
  const [selected, setSelected] = useState<HelpArticle | null>(null)

  const filtered = useMemo(() => {
    if (!query.trim()) return HELP_ARTICLES
    return HELP_ARTICLES.filter(
      (a) => fuzzyMatch(a.title, query) || fuzzyMatch(a.body, query)
    )
  }, [query])

  const grouped = useMemo(() => {
    const map: Partial<Record<HelpArticle['category'], HelpArticle[]>> = {}
    for (const a of filtered) {
      if (!map[a.category]) map[a.category] = []
      map[a.category]!.push(a)
    }
    return map
  }, [filtered])

  const categoryOrder: HelpArticle['category'][] = ['getting-started', 'features', 'troubleshooting', 'faq']

  if (!isOpen) return null

  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      {/* Backdrop */}
      <div className="absolute inset-0 bg-black/40" onClick={onClose} />

      {/* Panel */}
      <div className={cn(
        "relative w-96 h-full bg-background border-l border-border flex flex-col shadow-2xl",
        "animate-in slide-in-from-right duration-300"
      )}>
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-border">
          <div className="flex items-center gap-2">
            <HelpCircle className="h-4 w-4 text-primary" />
            <h2 className="font-semibold text-sm">Help Center</h2>
          </div>
          <Button variant="ghost" size="icon" className="h-7 w-7" onClick={onClose}>
            <X className="h-4 w-4" />
          </Button>
        </div>

        {selected ? (
          <ArticleView article={selected} onBack={() => setSelected(null)} />
        ) : (
          <>
            {/* Search */}
            <div className="p-3 border-b border-border">
              <div className="relative">
                <Search className="absolute left-2 top-2.5 h-3.5 w-3.5 text-muted-foreground" />
                <Input
                  placeholder="Search help articles..."
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  className="pl-7 h-8 text-xs"
                  autoFocus
                />
              </div>
            </div>

            {/* Article list */}
            <ScrollArea className="flex-1">
              <div className="p-3 space-y-4">
                {categoryOrder.map((cat) => {
                  const articles = grouped[cat]
                  if (!articles?.length) return null
                  const Icon = CATEGORY_ICONS[cat]
                  return (
                    <div key={cat}>
                      <div className="flex items-center gap-1.5 mb-1.5 px-1">
                        <Icon className="h-3 w-3 text-muted-foreground" />
                        <span className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">
                          {HELP_CATEGORIES[cat]}
                        </span>
                      </div>
                      <div className="space-y-0.5">
                        {articles.map((a) => (
                          <button
                            key={a.id}
                            onClick={() => setSelected(a)}
                            className="w-full flex items-center justify-between px-2 py-2 rounded-md text-xs text-left hover:bg-muted transition-colors"
                          >
                            <span className="flex-1 truncate">{a.title}</span>
                            <ChevronRight className="h-3 w-3 text-muted-foreground flex-shrink-0" />
                          </button>
                        ))}
                      </div>
                    </div>
                  )
                })}

                {filtered.length === 0 && (
                  <div className="text-center py-8 text-muted-foreground">
                    <HelpCircle className="h-8 w-8 mx-auto mb-2 opacity-20" />
                    <p className="text-xs">No articles matched "{query}"</p>
                  </div>
                )}
              </div>
            </ScrollArea>

            {/* Footer hint */}
            <div className="p-3 border-t border-border">
              <p className="text-[10px] text-muted-foreground text-center">
                Press <kbd className="px-1 py-0.5 bg-muted rounded font-mono">?</kbd> to open · <kbd className="px-1 py-0.5 bg-muted rounded font-mono">Esc</kbd> to close
              </p>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
