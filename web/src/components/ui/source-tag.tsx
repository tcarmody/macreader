import { cn } from '@/lib/utils'

// A small, consistent "source" block shown on every article — the feed/publisher
// name (e.g. "TechCrunch", "New York Times", "Techmeme"). Non-interactive so it
// can sit inside clickable cards without nesting buttons.
export function SourceTag({ name, className }: { name: string; className?: string }) {
  if (!name) return null
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
