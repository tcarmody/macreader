import { useState } from 'react'
import { Link2, ExternalLink, ChevronDown, ChevronUp, Loader2 } from 'lucide-react'
import { cn } from '@/lib/utils'
import type { RelatedLink } from '@/types'

interface RelatedLinksProps {
  relatedLinks: RelatedLink[] | null
  isLoading: boolean
  error: string | null
  hasTriggered: boolean
}

export function RelatedLinks({
  relatedLinks,
  isLoading,
  error,
  hasTriggered,
}: RelatedLinksProps) {
  const [showLinks, setShowLinks] = useState(true)

  // Show section if we have links OR if we're loading OR if there was an error
  const hasLinks = relatedLinks && relatedLinks.length > 0
  const shouldShow = hasLinks || isLoading || (hasTriggered && error)

  if (!shouldShow) {
    return null
  }

  return (
    <section className="mb-8 p-4 bg-blue-500/5 border border-blue-500/20 rounded-lg">
      <button
        onClick={() => setShowLinks(!showLinks)}
        className="w-full flex items-center justify-between text-left"
      >
        <div className="flex items-center gap-2">
          <Link2 className="h-4 w-4 text-blue-500" />
          <span className="font-semibold text-blue-700 dark:text-blue-300">
            Related Articles
          </span>
          {hasLinks && (
            <span className="text-xs text-muted-foreground">
              ({relatedLinks.length})
            </span>
          )}
        </div>
        {showLinks ? (
          <ChevronUp className="h-4 w-4 text-muted-foreground" />
        ) : (
          <ChevronDown className="h-4 w-4 text-muted-foreground" />
        )}
      </button>

      {showLinks && (
        <div className="mt-4 space-y-3">
          {/* Loading State */}
          {isLoading && (
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin" />
              <span>Finding related articles...</span>
            </div>
          )}

          {/* Error State */}
          {error && !isLoading && (
            <div className="text-sm text-red-600 dark:text-red-400">
              Failed to find related articles: {error}
            </div>
          )}

          {/* Links List */}
          {hasLinks && !isLoading && (
            <div className="space-y-3">
              {relatedLinks.map((link, index) => (
                <a
                  key={index}
                  href={link.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className={cn(
                    'block p-3 rounded-md border',
                    'bg-background hover:bg-accent/50',
                    'border-border hover:border-blue-500/30',
                    'transition-colors group'
                  )}
                >
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex-1 min-w-0">
                      <h4 className="font-medium text-sm mb-1 group-hover:text-blue-600 dark:group-hover:text-blue-400 line-clamp-2">
                        {link.title}
                      </h4>
                      {link.snippet && (
                        <p className="text-xs text-muted-foreground line-clamp-2 mb-2">
                          {link.snippet}
                        </p>
                      )}
                      <div className="flex items-center gap-2 text-xs text-muted-foreground">
                        <span className="font-mono">{link.domain}</span>
                        {link.published_date && (
                          <>
                            <span>•</span>
                            <span>{new Date(link.published_date).toLocaleDateString()}</span>
                          </>
                        )}
                        {link.score && (
                          <>
                            <span>•</span>
                            <span>Score: {(link.score * 100).toFixed(0)}%</span>
                          </>
                        )}
                      </div>
                    </div>
                    <ExternalLink className="h-4 w-4 text-muted-foreground group-hover:text-blue-500 flex-shrink-0 mt-0.5" />
                  </div>
                </a>
              ))}
            </div>
          )}
        </div>
      )}
    </section>
  )
}
