# Optional usage analytics

Introduced in `0.1.0-beta.7`; earlier releases have no analytics. PostHog EU project `307451` uses the free plan. [Dashboard](https://eu.posthog.com/project/307451/dashboard/1027294). Analytics is separate from required update requests and screen permission.

## Counting contract

All figures cover consenting browsers or app installations, not exact people. There is no website-to-app identity matching. Cleared preferences, multiple devices, withdrawal and later opt-in affect estimates. People blocked by Gatekeeper, who never launch, who decline, or who remain on older releases are absent.

| Metric | Definition |
| --- | --- |
| Website visitors | Unique browser IDs with a homepage `$pageview`. |
| Download interest | Unique `download_clicked` IDs divided by unique homepage visitors in the same period; also total clicks by `placement`: `hero`, `download_card`, `navbar`, `fixed_navbar`. A click does not prove a completed download or installation. |
| Traffic sources | Homepage visitors by referring domain and sanitized `utm_source`, `utm_medium`, `utm_campaign`; never arbitrary URL/query content. |
| New installations | Unique `app_first_launch` IDs. Opt-in within 24 hours of first seeing the analytics-enabled app, with no persisted settings/update history identifying an existing installation. Delayed opt-in is excluded; upgrades are not intentionally counted as new. |
| Setup success | Participating new installations producing `app_setup_completed` after a real Seamless Close presentation within seven days of first launch. Recent cohorts need seven days to mature. |
| Running installations | Unique `app_running_day` IDs over 7/30 days. An awake app sends at most one per UTC day, including when it never quits. This does not imply the person used a feature. |
| Feature users | Unique `seamless_close_used_day` IDs over 7/30 days. Only a successfully presented closing snapshot counts, not previews, sensor updates, canceled capture or cached opening. |
| Frequency | Over the last seven complete UTC days: number of used-day events / unique feature users, and sum of `seamless_close_daily.close_count` / unique installations with a daily summary. Counts arrive after day rollover or next launch. |
| Continued use | New `app_first_launch` installation cohorts producing `seamless_close_used_day` in later calendar weeks and months. Shows continued feature use without requiring app restarts; incomplete periods need time to mature. |

## Implementation and privacy

The undecided prompt lives in the Settings sidebar and disappears after either choice. It contains a short title, a usage-statistics subtitle with an inline details link, and the two choices. Privacy & about retains a compact card with the supplied chart icon, an inline privacy link and a switch after the decision. Allow uses the primary button treatment, while No thanks stays visible and directly actionable.

`UsageAnalyticsState` is a Codable state machine; `UsageAnalytics` owns the consent-gated EU HTTP client. No third-party SDK, autocapture, replay, session recording, surveys or person profiles. No analytics ID or usage is collected before consent. App events contain a random installation ID, app version, environment, schema version, UTC day and optional close count. They never reference screen content or sensor data. The project drops IPs; events disable GeoIP. Network providers still handle source IPs in transit.

Current-day totals remain local. The next awake tick finalizes each prior day's count once; event UUIDs persist across retries. The 60-second timer checks the day; uploads are asynchronous, at most once per five minutes except opt-in. No network or disk write occurs inside `recordClose`; state is saved on the next tick and sleep/quit. Abrupt termination can lose recent counts. Each consented tick removes queued events older than the 30-day retry window before an upload and limits the queue to 128 events. Local records can remain on disk longer while the app is closed; cleanup resumes when it next runs. Withdrawing cancels in-flight work, discards queued data and removes the ID. Later opt-in uses a new ID and never backfills disabled time. Already received events require a separate deletion request.

The current free PostHog plan caps usage and provides a one-year window for querying analytics events. This reporting window does not guarantee deletion of older data; see [PostHog’s retention information](https://posthog.com/docs/data/events-retention). The dashboard explicitly requires `environment=production`; test fixtures and local previews use `test`. Website and app IDs have separate prefixes and are never merged. Do not claim complete population totals, completed downloads, time spent watching the screen, or precise individual gesture timing.

## Development and rollout

- Developer bundles disable analytics networking by default, even if consent is allowed. `GLISSFORM_ANALYTICS_TEST=1` permits explicit test uploads labelled `test`; never change the environment field to manufacture production data.
- `scripts/test.sh` checks consent, daily counts, persistence, upgrade exclusion, expiry and retry/withdrawal using an intercepted URLSession. Automated tests never contact PostHog. Rendering/lifecycle tests do not start analytics.
- Before publication, review the new Settings choice and physically verify close/reversal, sleep/wake and quit. Automated checks do not prove physical behavior.
- Deploy the website privacy page and consent controls first, including its updated restricted deployment receiver. Then prepare a separately authorized app release and verify real events with an explicitly opted-in release installation. The policy describes privacy practices without app-version references; update it when those practices change.
- Keep the project token in client code: it is a public ingestion token, not a private account key. Never add personal PostHog API keys, screenshots or raw analytics exports to Git.
