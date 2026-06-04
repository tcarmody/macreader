import { Separator, type SeparatorProps } from 'react-resizable-panels'
import { cn } from '@/lib/utils'

// Re-export the primitives so consumers import everything from one place.
export { Group, Panel, useDefaultLayout } from 'react-resizable-panels'

/**
 * A styled drag handle for resizing panes. Renders react-resizable-panels'
 * `Separator` as a thin 1px divider with a wider invisible hit area and a
 * highlight on hover/drag.
 */
export function ResizeHandle({ className, ...props }: SeparatorProps) {
  return (
    <Separator
      {...props}
      className={cn(
        'relative w-px shrink-0 cursor-col-resize bg-border outline-none transition-colors duration-150',
        'hover:bg-primary/50 data-[disabled]:cursor-default data-[disabled]:hover:bg-border',
        // Widen the pointer hit area beyond the visible 1px line without shifting layout.
        'before:absolute before:inset-y-0 before:-left-1 before:-right-1 before:content-[""]',
        className,
      )}
    />
  )
}
