import { useState, useRef, useEffect } from 'react'
import {
  MessageCircle,
  Send,
  Loader2,
  Trash2,
  ChevronDown,
  ChevronUp,
  User,
  Bot,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { ScrollArea } from '@/components/ui/scroll-area'
import { Dialog, DialogContent, DialogFooter } from '@/components/ui/dialog'
import { useChatHistory, useSendChatMessage, useClearChatHistory } from '@/hooks/use-queries'
import type { ChatMessage } from '@/api/client'

interface ArticleChatProps {
  articleId: number
  isExpanded?: boolean
  onExpandedChange?: (expanded: boolean) => void
}

export function ArticleChat({
  articleId,
  isExpanded: externalIsExpanded,
  onExpandedChange
}: ArticleChatProps) {
  const [internalIsExpanded, setInternalIsExpanded] = useState(false)

  // Use external state if provided, otherwise use internal state
  const isExpanded = externalIsExpanded !== undefined ? externalIsExpanded : internalIsExpanded
  const setIsExpanded = (expanded: boolean | ((prev: boolean) => boolean)) => {
    const newValue = typeof expanded === 'function' ? expanded(isExpanded) : expanded
    if (onExpandedChange) {
      onExpandedChange(newValue)
    } else {
      setInternalIsExpanded(newValue)
    }
  }
  const [message, setMessage] = useState('')
  const [showClearConfirm, setShowClearConfirm] = useState(false)
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  const { data: chatHistory, isLoading: historyLoading } = useChatHistory(articleId)
  const sendMessage = useSendChatMessage()
  const clearHistory = useClearChatHistory()

  const messages = chatHistory?.messages || []
  const hasChat = chatHistory?.has_chat || false

  // Scroll to bottom when new messages arrive
  useEffect(() => {
    if (messagesEndRef.current && isExpanded) {
      messagesEndRef.current.scrollIntoView({ behavior: 'smooth' })
    }
  }, [messages.length, isExpanded])

  // Focus input when expanded
  useEffect(() => {
    if (isExpanded && inputRef.current) {
      inputRef.current.focus()
    }
  }, [isExpanded])

  const handleSend = async () => {
    if (!message.trim() || sendMessage.isPending) return

    const trimmedMessage = message.trim()
    setMessage('')

    try {
      await sendMessage.mutateAsync({ articleId, message: trimmedMessage })
    } catch {
      // Message failed, restore it
      setMessage(trimmedMessage)
    }
  }

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSend()
    }
  }

  const handleClear = () => {
    clearHistory.mutate(articleId)
    setShowClearConfirm(false)
  }

  const formatTime = (dateStr: string) => {
    const date = new Date(dateStr)
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
  }

  return (
    <section className="mb-8 border border-blue-500/20 rounded-lg overflow-hidden">
      {/* Header - always visible */}
      <button
        onClick={() => setIsExpanded(!isExpanded)}
        className="w-full flex items-center justify-between p-4 bg-blue-500/5 hover:bg-blue-500/10 transition-colors"
      >
        <div className="flex items-center gap-2">
          <MessageCircle className="h-4 w-4 text-blue-500" />
          <span className="font-semibold text-blue-700 dark:text-blue-300">
            Chat About This Article
          </span>
          {hasChat && (
            <Badge variant="secondary" className="text-xs">
              {messages.length} messages
            </Badge>
          )}
        </div>
        {isExpanded ? (
          <ChevronUp className="h-4 w-4 text-muted-foreground" />
        ) : (
          <ChevronDown className="h-4 w-4 text-muted-foreground" />
        )}
      </button>

      {/* Chat content - expandable */}
      {isExpanded && (
        <div className="border-t border-blue-500/20">
          {/* Messages area */}
          <ScrollArea className="h-64 p-4">
            {historyLoading ? (
              <div className="flex items-center justify-center h-full">
                <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
              </div>
            ) : messages.length === 0 ? (
              <div className="flex flex-col items-center justify-center h-full text-muted-foreground text-sm">
                <MessageCircle className="h-8 w-8 mb-2 opacity-50" />
                <p>No messages yet</p>
                <p className="text-xs mt-1">Ask questions or request summary changes</p>
              </div>
            ) : (
              <div className="space-y-4">
                {messages.map((msg: ChatMessage) => (
                  <div
                    key={msg.id}
                    className={cn(
                      'flex gap-3',
                      msg.role === 'user' ? 'justify-end' : 'justify-start'
                    )}
                  >
                    {msg.role === 'assistant' && (
                      <div className="flex-shrink-0 w-8 h-8 rounded-full bg-blue-500/10 flex items-center justify-center">
                        <Bot className="h-4 w-4 text-blue-500" />
                      </div>
                    )}
                    <div
                      className={cn(
                        'max-w-[80%] rounded-lg px-3 py-2 text-sm',
                        msg.role === 'user'
                          ? 'bg-primary text-primary-foreground'
                          : 'bg-muted'
                      )}
                    >
                      <p className="whitespace-pre-wrap">{msg.content}</p>
                      <div
                        className={cn(
                          'flex items-center gap-2 mt-1 text-xs',
                          msg.role === 'user'
                            ? 'text-primary-foreground/70'
                            : 'text-muted-foreground'
                        )}
                      >
                        <span>{formatTime(msg.created_at)}</span>
                        {msg.model_used && (
                          <Badge
                            variant="outline"
                            className={cn(
                              'text-[10px] px-1',
                              msg.role === 'user' && 'border-primary-foreground/30'
                            )}
                          >
                            {msg.model_used}
                          </Badge>
                        )}
                      </div>
                    </div>
                    {msg.role === 'user' && (
                      <div className="flex-shrink-0 w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center">
                        <User className="h-4 w-4 text-primary" />
                      </div>
                    )}
                  </div>
                ))}
                {sendMessage.isPending && (
                  <div className="flex gap-3 justify-start">
                    <div className="flex-shrink-0 w-8 h-8 rounded-full bg-blue-500/10 flex items-center justify-center">
                      <Bot className="h-4 w-4 text-blue-500" />
                    </div>
                    <div className="bg-muted rounded-lg px-3 py-2">
                      <Loader2 className="h-4 w-4 animate-spin" />
                    </div>
                  </div>
                )}
                <div ref={messagesEndRef} />
              </div>
            )}
          </ScrollArea>

          {/* Input area */}
          <div className="border-t border-blue-500/20 p-4">
            <div className="flex gap-2">
              <Input
                ref={inputRef}
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                onKeyDown={handleKeyDown}
                placeholder="Ask a question or request summary changes..."
                disabled={sendMessage.isPending}
                className="flex-1"
              />
              <Button
                size="icon"
                onClick={handleSend}
                disabled={!message.trim() || sendMessage.isPending}
              >
                {sendMessage.isPending ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <Send className="h-4 w-4" />
                )}
              </Button>
              {hasChat && (
                <Button
                  size="icon"
                  variant="ghost"
                  className="text-muted-foreground hover:text-destructive"
                  onClick={() => setShowClearConfirm(true)}
                >
                  <Trash2 className="h-4 w-4" />
                </Button>
              )}
            </div>
            {sendMessage.isError && (
              <p className="text-xs text-destructive mt-2">
                Failed to send message. Please try again.
              </p>
            )}
          </div>
        </div>
      )}

      {/* Clear confirmation dialog */}
      <Dialog
        isOpen={showClearConfirm}
        onClose={() => setShowClearConfirm(false)}
        title="Clear chat history?"
        icon={<Trash2 className="h-5 w-5 text-destructive" />}
      >
        <DialogContent>
          <p className="text-sm text-muted-foreground">
            This will delete all messages in this conversation.
            This action cannot be undone.
          </p>
        </DialogContent>
        <DialogFooter>
          <Button variant="ghost" onClick={() => setShowClearConfirm(false)}>
            Cancel
          </Button>
          <Button variant="destructive" onClick={handleClear}>
            Clear
          </Button>
        </DialogFooter>
      </Dialog>
    </section>
  )
}
