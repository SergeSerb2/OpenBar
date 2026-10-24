/** A host-issued candidate. Request-URL cookie policies expose metadata only. */
interface OpenBarCookieSession {
  readonly id: string;
  readonly header?: string;
  readonly source: string;
  readonly origin: string;
  readonly cachedAt?: number;
  readonly cacheKey?: string;
}

type OpenBarJSONPrimitive = boolean | number | string | null;
type OpenBarJSONValue = OpenBarJSONPrimitive | OpenBarJSONValue[] | { [key: string]: OpenBarJSONValue };

type OpenBarEndpoint =
  | string
  | {
      setting: string;
      policy: "https" | "https-or-loopback-http" | "https-or-private-network-http";
    };

type OpenBarAuth =
  | { type: "bearer" | "x-api-key"; secret: string }
  | { type: "header"; header: string; secret: string }
  | { type: "authorization-scheme"; scheme: string; secret: string };

interface OpenBarSetting {
  key: string;
  title: string;
  subtitle?: string;
  type?: "plain" | "secure";
}

interface OpenBarRateWindow {
  /** Optional label for generic cards and CLI text; trimmed, at most 256 UTF-8 bytes. */
  title?: string | null;
  usedPercent: number;
  windowMinutes?: number | null;
  resetsAt?: Date | string | null;
  resetDescription?: string | null;
  /** Absolute allowance; unit is credits, requests, or an ISO currency code. */
  quotaLimit?: number | null;
  quotaUnit?: string | null;
  nextRegenPercent?: number | null;
}

type OpenBarNamedRateWindow = {
  id: string;
  title: string;
  /** False keeps reset metadata visible without presenting unknown usage as a measured percentage. Defaults to true. */
  usageKnown?: boolean;
} & (OpenBarRateWindow | { window: OpenBarRateWindow });

interface OpenBarCostSnapshot {
  used: number;
  limit?: number | null;
  currency: string;
  period?: string | null;
  resetsAt?: Date | string | null;
  nextRegenAmount?: number | null;
  balance?: number | null;
}

interface OpenBarCostUsageEntry {
  date: string;
  inputTokens: number;
  outputTokens: number;
  /** Independent reported count; may exceed outputTokens and is not added to input + output totals. */
  reasoningTokens?: number | null;
  requests: number;
  cost: number;
  /** Portion of cost that is estimated rather than deducted by the provider. */
  estimatedCost?: number | null;
  model?: string | null;
}

interface OpenBarCostUsageSnapshot {
  currency: string;
  historyDays: number;
  historyLabel?: string | null;
  /** Inclusive YYYY-MM-DD end of the reported window. */
  windowEnd: string;
  entries: OpenBarCostUsageEntry[];
}

interface OpenBarIdentitySnapshot {
  email?: string | null;
  organization?: string | null;
  loginMethod?: string | null;
  accountID?: string | null;
}

interface OpenBarDetailRow {
  label: string;
  value: string;
  secondaryValue?: string | null;
  /** Plugin-computed severity; does not change the consumed-progress convention. */
  severity?: "normal" | "warning" | "critical" | null;
  /** Finite consumed fraction, from 0 through 1 inclusive. */
  progress?: number | null;
  /** Finite raw usage, independent of the display string and progress. */
  usageValue?: number | null;
}

interface OpenBarDetailChart {
  kind: "bars" | "line";
  title?: string | null;
  unit?: string | null;
  points: Array<{ label: string; value: number }>;
}

interface OpenBarDetailSection {
  title?: string | null;
  rows: OpenBarDetailRow[];
  chart?: OpenBarDetailChart | null;
}

interface OpenBarUsageSnapshot {
  /** Explicitly declares a successful response with no displayable usage or identity. Other fields are still validated. */
  empty?: boolean;
  /** Without empty: true, at least one window, cost, non-empty detail section, or identity field is required. */
  primary?: OpenBarRateWindow | null;
  secondary?: OpenBarRateWindow | null;
  tertiary?: OpenBarRateWindow | null;
  extraWindows?: OpenBarNamedRateWindow[] | null;
  cost?: OpenBarCostSnapshot | null;
  /** Exact provider-reported daily spend. The host validates and sums every numeric row. */
  costUsage?: OpenBarCostUsageSnapshot | null;
  identity?: OpenBarIdentitySnapshot | null;
  subscriptionRenewsAt?: Date | string | null;
  subscriptionExpiresAt?: Date | string | null;
  dataConfidence?: "exact" | "estimated" | "percentOnly" | "unknown";
  details?: OpenBarDetailSection[] | null;
}

/** Result metadata is validated by the host; card and persistence require a descriptor-owned allowlist. */
interface OpenBarFetchResult {
  usage: OpenBarUsageSnapshot;
  sourceLabel?: string;
  card?: {
    openAIAPIUsage: {
      live?: {
        windowMinutes: number;
        startTime: number;
        fetchedAt: number;
        buckets: Array<{
          startTime: number;
          models: Array<{
            name: string;
            inputTokens: number;
            cachedInputTokens: number;
            outputTokens: number;
            requests: number;
            /** Batch API subsets of inputTokens + outputTokens / requests, excluded from rate-limit utilization. */
            batchTokens?: number;
            batchRequests?: number;
          }>;
        }>;
      };
      historyDays: number;
      projectID?: string | null;
      daily: Array<{
        startTime: number;
        endTime: number;
        costUSD: number;
        requests: number;
        inputTokens: number;
        cachedInputTokens: number;
        outputTokens: number;
        totalTokens: number;
        lineItems: Array<{ name: string; costUSD: number }>;
        models: Array<{
          name: string;
          requests: number;
          inputTokens: number;
          cachedInputTokens: number;
          outputTokens: number;
          totalTokens: number;
        }>;
      }>;
    };
  };
  persist?: Record<string, string>;
}

interface OpenBarHTTPRequestOptions {
  /** Opaque session ID issued by browser.sessions for a request-url cookie policy. */
  cookieSession?: string;
  headers?: Readonly<Record<string, string>>;
  /** Hard deadline from transport start, 1–90 seconds (default 15); also bounded by the overall fetch deadline. */
  timeoutSeconds?: number;
  /** One native delayed retry for transient GET failures; POST is never retried. */
  retryPolicy?: "transientIdempotent";
}

interface OpenBarHTTPError extends Error {
  transportClass?: "timeout" | "dns" | "offline" | "cancelled" | "tls" | "connection" | "other" | "http";
  /** Foundation URLError code, preserved across both engines. */
  transportCode?: number;
  status?: number;
  /** Error-code eligibility for an idempotent retry, not a remaining retry budget. */
  retryable?: boolean;
}

interface OpenBarHTTPResponse {
  readonly url: string;
  /** `http-status` exposes non-2xx responses so the plugin can take over classification from the host. */
  status: number;
  headers: Readonly<Record<string, string>>;
}

interface OpenBarHTTPJSONResponse<T = unknown> extends OpenBarHTTPResponse {
  json: T;
}

interface OpenBarHTTPTextResponse extends OpenBarHTTPResponse {
  bodyText: string;
}

interface OpenBarRetryOptions {
  /** Requests the same one delayed retry used automatically for transient HTTP statuses; the host clamps it to 10 seconds. */
  retryAfterSeconds: number;
}

interface OpenBarFailures {
  authenticationExpired(message: unknown): Error;
  missingCredential(message: unknown): Error;
  permissionDenied(message: unknown): Error;
  rateLimited(message: unknown, options?: OpenBarRetryOptions): Error;
  providerUnavailable(message: unknown, options?: OpenBarRetryOptions): Error;
  parseFailure(message: unknown): Error;
  networkFailure(message: unknown, options?: OpenBarRetryOptions): Error;
  apiFailure(message: unknown, options?: OpenBarRetryOptions): Error;
}

type OpenBarPOSTOptions = OpenBarHTTPRequestOptions &
  ({ body: OpenBarJSONValue; form?: never } | { form: Readonly<Record<string, string>>; body?: never });

interface OpenBarPluginContext {
  readonly http: {
    getWithOptional(
      url: string,
      optional: string | (OpenBarPOSTOptions & { url: string; method: "POST" }),
      opts?: OpenBarHTTPRequestOptions & { optionalBudgetSeconds?: number },
    ): Promise<OpenBarHTTPTextResponse & { optional: OpenBarHTTPTextResponse | null }>;
    getJSON<T = unknown>(url: string, options?: OpenBarHTTPRequestOptions): Promise<OpenBarHTTPJSONResponse<T>>;
    get(url: string, options?: OpenBarHTTPRequestOptions): Promise<OpenBarHTTPTextResponse>;
    /** POST a JSON body or a host-encoded form and retain the response text. */
    post(url: string, options: OpenBarPOSTOptions): Promise<OpenBarHTTPTextResponse>;
    postJSON<T = unknown>(
      url: string,
      options: OpenBarHTTPRequestOptions & { body: OpenBarJSONValue },
    ): Promise<OpenBarHTTPJSONResponse<T>>;
  };
  readonly settings: {
    get(key: string): string | null;
    getSecret(key: string): string | null;
  };
  readonly browser: {
    readonly supportedBrowsers: string;
    availability(domain: string): "available" | "off" | "manual";
    acceptCookie(domain: string, session: OpenBarCookieSession): void;
    rejectCookie(domain: string, session?: OpenBarCookieSession): void;
    sessions(domain: string, options?: { cachedOnly?: boolean }): AsyncIterable<OpenBarCookieSession>;
    cookieHeader(domain: string): Promise<string>;
  };
  readonly html: {
    metaContent(html: string, name: string): string | null;
    matchFirst(html: string, regexSource: string, flags?: string): string | null;
  };
  readonly date: {
    now(): Date;
    iso(value: string): Date;
    unixSeconds(value: number): Date;
    unixMillis(value: number): Date;
    nextDailyReset(timeZone: string, hour: number): Date;
    /** Gregorian calendar arithmetic with Foundation end-of-month clamping, in the given IANA zone. */
    addMonths(date: Date, months: number, timeZone: string): Date;
  };
  readonly format: {
    /** Native en_US currency formatting, including decimal half-even rounding and signed zero. */
    currency(value: number, currencyCode: string): string;
    number(value: number, options?: { minimumFractionDigits?: number; maximumFractionDigits?: number }): string;
    usd(value: number): string;
    monthDay(value: Date | number | string): string;
  };
  readonly fail: Readonly<OpenBarFailures>;
  readonly env: {
    readonly timeZone: string;
  };
  readonly cache: {
    get<T = unknown>(key: string): T | undefined;
    set(key: string, value: unknown, ttlSeconds: number): void;
  };
  readonly storage: {
    get(key: string): string | null;
    set(key: string, value: string): void;
    remove(key: string): void;
  };
  readonly jwt: {
    decode<T = unknown>(token: string): T;
  };
  log(...values: unknown[]): void;
  pct(used: number, limit: number): number;
  amountFromPercent(percent: number, limit: number): number;
  isDetailLabel(value: unknown): boolean;
}

interface OpenBarProviderDefinition {
  id: string;
  name: string;
  /** `svg`: optional monochrome SVG (≤ 8 KB, canvas ≤ 4096; see docs/plugins.md) shown as a template image; invalid SVG falls back to the monogram. */
  icon?: { monogram?: string; tint?: string; svg?: string };
  /** Defaults to true: a switcher tab when Merge Icons is on. False keeps an appended card. */
  topLevel?: boolean;
  endpoints: OpenBarEndpoint[];
  auth?: OpenBarAuth;
  settings: OpenBarSetting[];
  /** Grants declared cookie access, HTTP status handling, or bounded non-secret persistent state. */
  capabilities?: Array<"browser-cookies" | "http-status" | "persistent-storage">;
  cookieDomains?: string[];
  snapshotPolicy?: { percent: "clamp" | "preserve-overage" };
  /** Bundled-only, host-owned per-profile cookie selection without persistent session caching. */
  cookiePolicy?: {
    selection: "request-url" | "ranked-source-domains";
    cache: "nonpersistent" | "validated-single-entry";
    sourceDomains?: string[];
    requiredCookies?: string[];
    missingCookies?: "reject" | "omit";
    imports?: "app-interactive" | "access-gated";
    /** Restrict reads to the configured browser profile and revalidate ownership before publication. */
    store?: "selected-profile";
    /** URL whose requiredCookies establish session ownership; required for selected-profile. */
    sessionURL?: string;
    sessionFile?: { tokenField: string; cookieName: string };
    /** Host-only echo of a required cookie into a custom X- header on one declared HTTPS origin. */
    headerEcho?: { origin: string; cookie: string; header: string };
  };
  fetchUsage(
    ctx: OpenBarPluginContext,
  ): OpenBarUsageSnapshot | OpenBarFetchResult | Promise<OpenBarUsageSnapshot | OpenBarFetchResult>;
}

declare function defineProvider(definition: OpenBarProviderDefinition): void;
