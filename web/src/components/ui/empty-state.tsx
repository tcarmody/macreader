import type { ComponentType, ReactNode } from 'react'
import { cn } from '@/lib/utils'

interface EmptyStateProps {
  /** Icon component to display */
  icon: ComponentType<{ className?: string }>
  /** Main message */
  title: string
  /** Optional secondary description */
  description?: string
  /** Optional action button or content */
  action?: ReactNode
  /** Additional class names */
  className?: string
}

/**
 * Reusable empty state component for lists and views with no data.
 *
 * @example
 * ```tsx
 * <EmptyState
 *   icon={Inbox}
 *   title="No articles"
 *   description="Subscribe to feeds to see articles here"
 * />
 * ```
 */
export function EmptyState({
  icon: Icon,
  title,
  description,
  action,
  className,
}: EmptyStateProps) {
  return (
    <div className={cn("flex-1 flex items-center justify-center text-muted-foreground", className)}>
      <div className="text-center">
        <Icon className="h-12 w-12 mx-auto mb-4 opacity-20" />
        <p className="font-medium">{title}</p>
        {description && (
          <p className="text-sm mt-1 opacity-80">{description}</p>
        )}
        {action && (
          <div className="mt-4">{action}</div>
        )}
      </div>
    </div>
  )
}
