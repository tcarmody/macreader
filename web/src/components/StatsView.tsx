import { useState } from 'react'
import { BookOpen, Clock, Bookmark, Sparkles, BarChart2, AlertCircle } from 'lucide-react'
import { ScrollArea } from '@/components/ui/scroll-area'
import { Skeleton } from '@/components/ui/skeleton'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'
import { useReadingStats } from '@/hooks/use-queries'

type PeriodValue = '7d' | '30d' | '90d'

const PERIODS: { value: PeriodValue; label: string }[] = [
  { value: '7d', label: '7 days' },
  { value: '30d', label: '30 days' },
  { value: '90d', label: '90 days' },
]

function formatDuration(minutes: number): string {
  if (minutes < 1) return '< 1 min'
  const hrs = Math.floor(minutes / 60)
  const mins = Math.round(minutes % 60)
  if (hrs === 0) return `${mins} min`
  if (mins === 0) return `${hrs} hr`
  return `${hrs} hr ${mins} min`
}

function StatCard({
  label,
  value,
  sub,
  icon: Icon,
}: {
  label: string
  value: string
  sub?: string
  icon: React.ComponentType<{ className?: string }>
}) {
  return (
    <div className="bg-card border border-border rounded-lg p-4">
      <div className="flex items-center gap-1.5 mb-2">
        <Icon className="h-3.5 w-3.5 text-muted-foreground" />
        <span className="text-xs text-muted-foreground">{label}</span>
      </div>
      <div className="text-2xl font-bold leading-none">{value}</div>
      {sub && <div className="text-xs text-muted-foreground mt-1.5">{sub}</div>}
    </div>
  )
}

function ActivityBars({ data }: { data: Record<string, number> }) {
  const entries = Object.entries(data).sort(([a], [b]) => a.localeCompare(b))
  if (entries.length === 0) return null
  const max = Math.max(...entries.map(([, v]) => v), 1)

  return (
    <div>
      <div className="flex items-end gap-0.5 h-16">
        {entries.map(([date, count]) => (
          <div
            key={date}
            className="flex-1 bg-primary/60 rounded-sm transition-all"
            style={{ height: `${Math.max((count / max) * 100, count > 0 ? 6 : 0)}%` }}
            title={`${date}: ${count}`}
          />
        ))}
      </div>
      <div className="flex justify-between text-xs text-muted-foreground mt-1.5">
        <span>{entries[0]?.[0]}</span>
        <span>{entries[entries.length - 1]?.[0]}</span>
      </div>
    </div>
  )
}

function HorizontalBar({
  label,
  value,
  max,
}: {
  label: string
  value: number
  max: number
}) {
  return (
    <div className="flex items-center gap-2 py-1">
      <span className="text-sm truncate flex-1 min-w-0">{label}</span>
      <div className="w-24 h-1.5 bg-muted rounded-full overflow-hidden shrink-0">
        <div
          className="h-full bg-primary/60 rounded-full"
          style={{ width: `${(value / max) * 100}%` }}
        />
      </div>
      <span className="text-xs text-muted-foreground w-5 text-right shrink-0">{value}</span>
    </div>
  )
}

function SectionHeading({ children }: { children: React.ReactNode }) {
  return (
    <h2 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground mb-3">
      {children}
    </h2>
  )
}

function StatsSkeleton() {
  return (
    <div className="max-w-3xl mx-auto px-6 py-6 space-y-8">
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        {[1, 2, 3, 4].map((i) => (
          <Skeleton key={i} className="h-20" />
        ))}
      </div>
      <Skeleton className="h-28" />
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
        <Skeleton className="h-48" />
        <Skeleton className="h-48" />
      </div>
    </div>
  )
}

export function StatsView() {
  const [period, setPeriod] = useState<PeriodValue>('30d')
  const { data: stats, isLoading, error } = useReadingStats('rolling', period)

  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      {/* Header */}
      <div className="flex items-center gap-2 px-4 py-3 border-b border-border bg-card shrink-0">
        <BarChart2 className="h-4 w-4 text-muted-foreground" />
        <span className="font-medium text-sm">Reading Statistics</span>
        <div className="ml-auto flex rounded-md border border-border overflow-hidden text-xs">
          {PERIODS.map(({ value, label }, i) => (
            <button
              key={value}
              className={cn(
                'px-3 py-1.5 transition-colors',
                i > 0 && 'border-l border-border',
                period === value
                  ? 'bg-secondary text-secondary-foreground'
                  : 'text-muted-foreground hover:text-foreground hover:bg-muted'
              )}
              onClick={() => setPeriod(value)}
            >
              {label}
            </button>
          ))}
        </div>
      </div>

      <ScrollArea className="flex-1">
        {isLoading ? (
          <StatsSkeleton />
        ) : error ? (
          <div className="flex flex-col items-center justify-center h-64 gap-3 text-center p-8">
            <AlertCircle className="h-8 w-8 text-muted-foreground" />
            <p className="text-sm text-muted-foreground">
              {error instanceof Error ? error.message : 'Could not load statistics'}
            </p>
          </div>
        ) : stats ? (
          <div className="max-w-3xl mx-auto px-6 py-6 space-y-8">
            {/* Stat cards */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
              <StatCard
                label="Articles Read"
                value={stats.reading.articles_read.toString()}
                icon={BookOpen}
              />
              <StatCard
                label="Time Spent"
                value={formatDuration(stats.reading.total_reading_time_minutes)}
                sub={`~${formatDuration(stats.reading.avg_reading_time_minutes)} avg`}
                icon={Clock}
              />
              <StatCard
                label="Bookmarked"
                value={stats.reading.bookmarks_added.toString()}
                icon={Bookmark}
              />
              <StatCard
                label="AI Summaries"
                value={stats.summarization.summarized_articles.toString()}
                sub={`${Math.round(stats.summarization.summarization_rate * 100)}% of articles`}
                icon={Sparkles}
              />
            </div>

            {/* Activity chart */}
            {Object.keys(stats.reading.read_by_day).length > 0 && (
              <div>
                <SectionHeading>Reading Activity</SectionHeading>
                <div className="bg-card border border-border rounded-lg p-4">
                  <ActivityBars data={stats.reading.read_by_day} />
                </div>
              </div>
            )}

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
              {/* Top feeds */}
              {Object.keys(stats.reading.read_by_feed).length > 0 && (() => {
                const topFeeds = Object.entries(stats.reading.read_by_feed)
                  .sort(([, a], [, b]) => b - a)
                  .slice(0, 8)
                const max = topFeeds[0]?.[1] ?? 1
                return (
                  <div>
                    <SectionHeading>Top Feeds</SectionHeading>
                    <div className="bg-card border border-border rounded-lg px-4 py-2">
                      {topFeeds.map(([feed, count]) => (
                        <HorizontalBar key={feed} label={feed} value={count} max={max} />
                      ))}
                    </div>
                  </div>
                )
              })()}

              {/* Top topics */}
              {stats.topics.most_common.length > 0 && (
                <div>
                  <SectionHeading>Top Topics</SectionHeading>
                  <div className="bg-card border border-border rounded-lg p-4">
                    <div className="flex flex-wrap gap-2">
                      {stats.topics.most_common.slice(0, 12).map((topic) => (
                        <Badge key={topic.label} variant="secondary" className="text-xs gap-1">
                          {topic.label}
                          <span className="text-muted-foreground">{topic.count}</span>
                        </Badge>
                      ))}
                    </div>
                  </div>
                </div>
              )}
            </div>

            {/* AI usage */}
            {Object.keys(stats.summarization.model_breakdown).length > 0 && (
              <div>
                <SectionHeading>AI Usage</SectionHeading>
                <div className="bg-card border border-border rounded-lg p-4">
                  <div className="flex gap-6 flex-wrap mb-2">
                    {Object.entries(stats.summarization.model_breakdown).map(([model, count]) => (
                      <div key={model} className="text-sm">
                        <span className="font-semibold">{count}</span>
                        <span className="text-muted-foreground ml-1 text-xs">{model}</span>
                      </div>
                    ))}
                  </div>
                  <p className="text-xs text-muted-foreground">
                    {stats.summarization.avg_per_day.toFixed(1)} per day ·{' '}
                    {stats.summarization.avg_per_week.toFixed(1)} per week
                  </p>
                </div>
              </div>
            )}
          </div>
        ) : null}
      </ScrollArea>
    </div>
  )
}
