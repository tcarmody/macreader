import * as React from 'react'
import { X } from 'lucide-react'
import { cn } from '@/lib/utils'
import { useAppStore } from '@/store/app-store'

interface CoachMarkProps {
  /** Unique identifier for this coach mark */
  hintId: string
  /** Title shown in the callout */
  title: string
  /** Body text shown in the callout */
  body: string
  side?: 'top' | 'right' | 'bottom' | 'left'
  className?: string
}

const positionClasses = {
  top: 'bottom-full left-1/2 -translate-x-1/2 mb-3',
  right: 'left-full top-1/2 -translate-y-1/2 ml-3',
  bottom: 'top-full left-1/2 -translate-x-1/2 mt-3',
  left: 'right-full top-1/2 -translate-y-1/2 mr-3',
}

export function CoachMark({ hintId, title, body, side = 'bottom', className }: CoachMarkProps) {
  const [open, setOpen] = React.useState(false)
  const { isHintActive, dismissHint } = useAppStore()

  if (!isHintActive(hintId, 1)) return null

  const handleDismiss = (e: React.MouseEvent) => {
    e.stopPropagation()
    dismissHint(hintId)
    setOpen(false)
  }

  return (
    <span className={cn('relative inline-flex', className)}>
      {/* Pulsing dot trigger */}
      <span
        className="relative flex h-2 w-2 cursor-pointer"
        onMouseEnter={() => setOpen(true)}
        onMouseLeave={() => setOpen(false)}
        onClick={(e) => { e.stopPropagation(); setOpen((v) => !v) }}
      >
        <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-primary opacity-75" />
        <span className="relative inline-flex rounded-full h-2 w-2 bg-primary" />
      </span>

      {/* Callout */}
      {open && (
        <div
          className={cn(
            'absolute z-50 w-60 p-3 rounded-lg shadow-lg border bg-popover text-popover-foreground',
            'animate-in fade-in-0 zoom-in-95 duration-150',
            positionClasses[side]
          )}
          onMouseEnter={() => setOpen(true)}
          onMouseLeave={() => setOpen(false)}
        >
          <div className="flex items-start justify-between gap-2 mb-1">
            <p className="text-xs font-semibold">{title}</p>
            <button
              onClick={handleDismiss}
              className="text-muted-foreground hover:text-foreground flex-shrink-0 mt-0.5"
              title="Dismiss"
            >
              <X className="h-3 w-3" />
            </button>
          </div>
          <p className="text-xs text-muted-foreground leading-relaxed">{body}</p>
          <button
            onClick={handleDismiss}
            className="mt-2 text-[10px] text-primary hover:underline"
          >
            Got it
          </button>
        </div>
      )}
    </span>
  )
}
