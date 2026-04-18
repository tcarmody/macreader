import * as React from 'react'
import { cn } from '@/lib/utils'
import { useAppStore } from '@/store/app-store'

interface SmartTooltipProps {
  /** Unique identifier used to track view count in the store */
  hintId: string
  /** Stop showing after this many hover views (default: 5) */
  maxViews?: number
  children: React.ReactNode
  /** Tooltip title (bold) */
  title: string
  /** Tooltip body text */
  body: string
  side?: 'top' | 'right' | 'bottom' | 'left'
  className?: string
}

const positionClasses = {
  top: 'bottom-full left-1/2 -translate-x-1/2 mb-2',
  right: 'left-full top-1/2 -translate-y-1/2 ml-2',
  bottom: 'top-full left-1/2 -translate-x-1/2 mt-2',
  left: 'right-full top-1/2 -translate-y-1/2 mr-2',
}

export function SmartTooltip({
  hintId,
  maxViews = 5,
  children,
  title,
  body,
  side = 'top',
  className,
}: SmartTooltipProps) {
  const [visible, setVisible] = React.useState(false)
  const { recordHintView, isHintActive } = useAppStore()

  const active = isHintActive(hintId, maxViews)

  const handleEnter = () => {
    if (!active) return
    recordHintView(hintId)
    setVisible(true)
  }

  const handleLeave = () => setVisible(false)

  return (
    <div
      className={cn('relative inline-block', className)}
      onMouseEnter={handleEnter}
      onMouseLeave={handleLeave}
    >
      {children}
      {visible && active && (
        <div
          className={cn(
            'absolute z-50 w-56 p-3 rounded-lg shadow-lg border bg-popover text-popover-foreground',
            'animate-in fade-in-0 zoom-in-95 duration-150',
            positionClasses[side]
          )}
        >
          <p className="text-xs font-semibold mb-1">{title}</p>
          <p className="text-xs text-muted-foreground leading-relaxed">{body}</p>
        </div>
      )}
    </div>
  )
}
