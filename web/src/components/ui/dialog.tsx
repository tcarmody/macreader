import { ReactNode } from 'react'
import { X } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from './button'

interface DialogProps {
  /** Whether the dialog is visible */
  isOpen: boolean
  /** Called when the dialog should close (backdrop click or close button) */
  onClose: () => void
  /** Dialog title */
  title: string
  /** Optional icon to display next to the title */
  icon?: ReactNode
  /** Dialog content */
  children: ReactNode
  /** Max width variant */
  maxWidth?: 'sm' | 'md' | 'lg'
  /** Additional class names for the dialog container */
  className?: string
}

const maxWidthClasses = {
  sm: 'max-w-sm',
  md: 'max-w-md',
  lg: 'max-w-lg',
}

/**
 * Reusable dialog component with backdrop, header, and close button.
 *
 * @example
 * ```tsx
 * <Dialog
 *   isOpen={isOpen}
 *   onClose={onClose}
 *   title="Add Feed"
 *   icon={<Rss className="h-5 w-5" />}
 * >
 *   <form>...</form>
 * </Dialog>
 * ```
 */
export function Dialog({
  isOpen,
  onClose,
  title,
  icon,
  children,
  maxWidth = 'md',
  className,
}: DialogProps) {
  if (!isOpen) return null

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/50"
        onClick={onClose}
      />

      {/* Dialog */}
      <div
        className={cn(
          "relative bg-background border border-border rounded-lg shadow-xl w-full mx-4",
          maxWidthClasses[maxWidth],
          className
        )}
      >
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-border">
          <div className="flex items-center gap-2">
            {icon}
            <h2 className="text-lg font-semibold">{title}</h2>
          </div>
          <Button variant="ghost" size="icon" onClick={onClose}>
            <X className="h-4 w-4" />
          </Button>
        </div>

        {/* Content */}
        <div>{children}</div>
      </div>
    </div>
  )
}

interface DialogContentProps {
  children: ReactNode
  className?: string
}

/**
 * Optional wrapper for dialog content with standard padding.
 */
export function DialogContent({ children, className }: DialogContentProps) {
  return (
    <div className={cn("p-4", className)}>
      {children}
    </div>
  )
}

interface DialogFooterProps {
  children: ReactNode
  className?: string
}

/**
 * Optional wrapper for dialog footer with standard layout.
 */
export function DialogFooter({ children, className }: DialogFooterProps) {
  return (
    <div className={cn("flex justify-end gap-2 p-4 border-t border-border", className)}>
      {children}
    </div>
  )
}
