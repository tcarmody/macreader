import * as React from "react"
import { Loader2 } from "lucide-react"
import { Button, ButtonProps } from "./button"

export interface LoadingButtonProps extends ButtonProps {
  /** Whether the button is in a loading state */
  isLoading?: boolean
  /** Text to show while loading (defaults to children) */
  loadingText?: string
}

/**
 * Button component with built-in loading state.
 *
 * @example
 * ```tsx
 * <LoadingButton
 *   isLoading={isPending}
 *   loadingText="Saving..."
 *   onClick={handleSave}
 * >
 *   Save
 * </LoadingButton>
 * ```
 */
const LoadingButton = React.forwardRef<HTMLButtonElement, LoadingButtonProps>(
  ({ isLoading, loadingText, children, disabled, ...props }, ref) => {
    return (
      <Button
        ref={ref}
        disabled={disabled || isLoading}
        {...props}
      >
        {isLoading ? (
          <>
            <Loader2 className="h-4 w-4 mr-2 animate-spin" />
            {loadingText || children}
          </>
        ) : (
          children
        )}
      </Button>
    )
  }
)
LoadingButton.displayName = "LoadingButton"

export { LoadingButton }
