import { useState } from 'react'
import { X, Loader2, Rss } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useAddFeed } from '@/hooks/use-queries'

interface AddFeedDialogProps {
  isOpen: boolean
  onClose: () => void
}

export function AddFeedDialog({ isOpen, onClose }: AddFeedDialogProps) {
  const [url, setUrl] = useState('')
  const [name, setName] = useState('')
  const [category, setCategory] = useState('')
  const [error, setError] = useState('')

  const addFeed = useAddFeed()

  if (!isOpen) return null

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')

    if (!url.trim()) {
      setError('Please enter a feed URL')
      return
    }

    try {
      await addFeed.mutateAsync({
        url: url.trim(),
        name: name.trim() || undefined,
        category: category.trim() || undefined,
      })
      setUrl('')
      setName('')
      setCategory('')
      onClose()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to add feed')
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div className="absolute inset-0 bg-black/50" onClick={onClose} />

      {/* Dialog */}
      <div className="relative bg-background border border-border rounded-lg shadow-xl w-full max-w-md mx-4">
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-border">
          <div className="flex items-center gap-2">
            <Rss className="h-5 w-5" />
            <h2 className="text-lg font-semibold">Add Feed</h2>
          </div>
          <Button variant="ghost" size="icon" onClick={onClose}>
            <X className="h-4 w-4" />
          </Button>
        </div>

        {/* Content */}
        <form onSubmit={handleSubmit} className="p-4 space-y-4">
          <div>
            <label className="block text-sm font-medium mb-1">
              Feed URL <span className="text-destructive">*</span>
            </label>
            <Input
              value={url}
              onChange={(e) => setUrl(e.target.value)}
              placeholder="https://example.com/feed.xml"
              autoFocus
            />
          </div>

          <div>
            <label className="block text-sm font-medium mb-1">
              Name (optional)
            </label>
            <Input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="My Favorite Blog"
            />
            <p className="text-xs text-muted-foreground mt-1">
              Leave empty to use the feed's title
            </p>
          </div>

          <div>
            <label className="block text-sm font-medium mb-1">
              Category (optional)
            </label>
            <Input
              value={category}
              onChange={(e) => setCategory(e.target.value)}
              placeholder="Tech, News, etc."
            />
          </div>

          {error && (
            <div className="p-3 bg-destructive/10 border border-destructive/20 rounded-md text-sm text-destructive">
              {error}
            </div>
          )}

          <div className="flex justify-end gap-2 pt-2">
            <Button type="button" variant="outline" onClick={onClose}>
              Cancel
            </Button>
            <Button type="submit" disabled={addFeed.isPending}>
              {addFeed.isPending ? (
                <>
                  <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                  Adding...
                </>
              ) : (
                'Add Feed'
              )}
            </Button>
          </div>
        </form>
      </div>
    </div>
  )
}
