import { type ClassValue, clsx } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function formatDate(date: string | Date): string {
  const d = new Date(date)
  const now = new Date()
  const diff = now.getTime() - d.getTime()
  const days = Math.floor(diff / (1000 * 60 * 60 * 24))

  // Handle future dates (clock skew) by treating as "Just now"
  if (diff < 0) {
    return 'Just now'
  }

  if (days === 0) {
    const hours = Math.floor(diff / (1000 * 60 * 60))
    if (hours === 0) {
      const minutes = Math.floor(diff / (1000 * 60))
      return minutes <= 1 ? 'Just now' : `${minutes}m ago`
    }
    return hours === 1 ? '1h ago' : `${hours}h ago`
  }
  if (days === 1) return 'Yesterday'
  if (days < 7) return `${days}d ago`

  return d.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: d.getFullYear() !== now.getFullYear() ? 'numeric' : undefined
  })
}

export function formatFullDate(date: string | Date): string {
  return new Date(date).toLocaleDateString('en-US', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit'
  })
}

export function truncate(str: string, length: number): string {
  if (str.length <= length) return str
  return str.slice(0, length) + '...'
}

export function stripHtml(html: string): string {
  const doc = new DOMParser().parseFromString(html, 'text/html')
  return doc.body.textContent || ''
}

export function getInitials(name: string): string {
  return name
    .split(' ')
    .map(word => word[0])
    .join('')
    .toUpperCase()
    .slice(0, 2)
}

export function getDomain(url: string): string {
  try {
    return new URL(url).hostname.replace('www.', '')
  } catch {
    return url
  }
}

/**
 * Convert straight quotes to typographically correct smart quotes.
 * Handles double quotes, single quotes, and apostrophes.
 *
 * Unicode characters used:
 * - \u201C = " (left double quote)
 * - \u201D = " (right double quote)
 * - \u2018 = ' (left single quote)
 * - \u2019 = ' (right single quote / apostrophe)
 */
export function smartQuotes(text: string): string {
  return text
    // Double quotes: opening after whitespace/start, closing before whitespace/end/punctuation
    .replace(/"(\S)/g, '\u201C$1')       // Opening double quote
    .replace(/(\S)"/g, '$1\u201D')       // Closing double quote
    .replace(/"\s/g, '\u201D ')          // Closing double quote before space
    .replace(/\s"/g, ' \u201C')          // Opening double quote after space
    .replace(/^"/g, '\u201C')            // Opening double quote at start
    .replace(/"$/g, '\u201D')            // Closing double quote at end
    // Single quotes / apostrophes
    .replace(/(\w)'(\w)/g, '$1\u2019$2') // Apostrophe within words (don't, it's)
    .replace(/'(\S)/g, '\u2018$1')       // Opening single quote
    .replace(/(\S)'/g, '$1\u2019')       // Closing single quote
    .replace(/'\s/g, '\u2019 ')          // Closing single quote before space
    .replace(/\s'/g, ' \u2018')          // Opening single quote after space
    .replace(/^'/g, '\u2018')            // Opening single quote at start
    .replace(/'$/g, '\u2019')            // Closing single quote at end
}
