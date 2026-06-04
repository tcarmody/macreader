import { cn } from '@/lib/utils'

// A small, consistent "source" block shown on every article — the feed/publisher
// name (e.g. "TechCrunch", "New York Times", "Techmeme"). Non-interactive so it
// can sit inside clickable cards without nesting buttons.
//
// - 'pill'  : rounded chip with a dot (used in the reader header)
// - 'caps'  : small uppercase box, shown at the end of card headlines
export function SourceTag({
  name,
  className,
  variant = 'pill',
}: {
  name: string
  className?: string
  variant?: 'pill' | 'caps'
}) {
  if (!name) return null

  if (variant === 'caps') {
    return (
      <span
        className={cn(
          'inline-flex max-w-full items-center rounded-md border border-border bg-muted/50 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground',
          className
        )}
      >
        <span className="truncate">{name}</span>
      </span>
    )
  }

  return (
    <span
      className={cn(
        'inline-flex max-w-full items-center gap-1.5 rounded-full border border-border bg-muted/60 px-2.5 py-0.5 text-xs font-medium text-foreground/80',
        className
      )}
    >
      <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-primary/60" />
      <span className="truncate">{name}</span>
    </span>
  )
}
