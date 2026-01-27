import { cn } from '@/lib/utils'

interface BadgePulseProps {
  className?: string
}

/**
 * A small pulsing indicator to draw attention to unused features.
 * Displays as a subtle animated dot.
 */
export function BadgePulse({ className }: BadgePulseProps) {
  return (
    <span className="relative flex h-2 w-2">
      <span
        className={cn(
          "animate-ping absolute inline-flex h-full w-full rounded-full opacity-75",
          className || "bg-primary"
        )}
      />
      <span
        className={cn(
          "relative inline-flex rounded-full h-2 w-2",
          className || "bg-primary"
        )}
      />
    </span>
  )
}
