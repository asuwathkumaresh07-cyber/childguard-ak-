# Family Guard 🛡️

## Child-specific controls and activity

Each child's Activity Monitor has **Categorized Logs**, **Web Shield**,
**Apps & Limits**, **Location & Zones**, and **Other**. Categorized Logs contains
the live event feed and a single usage graph with **Daily** and **Hourly** modes.
The graph shows the change from the previous day in percent and elapsed time;
sessions crossing midnight are split between days. The VPN icon displays the
device's reported ON/OFF state and marks reports older than three minutes as
last reported rather than current.

The interface uses white surfaces, blue controls, and red for warnings. Prebuilt
animated icons come from `not_static_icons`; library effects use `flutter_animate`.
Background waves, card shimmer, ripple rings, and the robot mascot are removed.
Motion respects the device's reduced-animation setting.

Loading screens use a floating 3D-style blue icon with perspective rotation,
depth, and drag-to-tilt interaction. Compact versions appear in sign-in and
approval buttons. Loaders follow real operation state and do not add artificial
delays or simulated progress.

[Narrow-phone layout preview](artifacts/activity-preview.png) uses sample activity
to show the updated graph and VPN status layout.

Parents can add website and app blocks, choose website content categories, set
daily limits, and assign app activity categories for the selected child. Existing
family rules still apply and are labeled in the controls. App categories, task
rewards, autonomy settings, and mood check-ins are in Other.
Weekly insight cards and simulated alert buttons have been removed. Alerts are
driven by recorded device events; background push still requires the Firebase
configuration described below.

For existing databases, apply
[child-specific rules](supabase/migrations/202610220001_child_scoped_rules.sql)
after the earlier migrations. This adds child-scoped rules with row-level
security, an atomic category update function, and Realtime publication entries.
Apply it before installing an updated app that uses these controls.

A dual-app Flutter & Android solution for family network protection and activity monitoring.

- **Parent App** (`apps/parent`): A blue-and-white family dashboard with animated feature icons, child-specific controls, daily/hourly activity charts, live location/geofence views, website-category filtering, custom domain blocks, and app blocking.
- **Child App** (`apps/child`): Enforces configured website rules through an Android `VpnService`, queues DNS and app-usage events in a private SQLite database, syncs them to Supabase, and enforces app blocks and daily limits with `AccessibilityService`.
- **Backend & Database**: Fully integrated with **Supabase** (PostgreSQL, Auth, RLS, Realtime) with an offline fallback mode when dummy keys are used.

---

## Authentication and first use

The APKs connect to the configured Supabase project. Use real email addresses and passwords; `parent@demo.local` and password `1234` are not cloud login credentials.

1. Open **Parent App** and create the parent account with a valid email address and a password of at least 6 characters.
2. Confirm the email if Supabase asks, then sign in.
3. On the Parent dashboard, choose **Create child** and set the child's name, email address, and temporary password.
4. Give those credentials to the child. Open **Child App** and sign in. The new child account is linked to the parent's family automatically.

Only the Parent app offers account registration. The Child app is sign-in only; a parent must create the child account first.

After opening a child's detail page in the Parent app, use **Controls** to choose **Strict** or **Friendly** protection mode and generate a one-use code to turn protection on or off. The child enters that code in the Child app; each code expires after 10 minutes and authorizes only the selected action. Strict mode disables child-initiated pause requests. Friendly mode lets the child request a pause; a parent must approve it and provide a fresh OFF code before the VPN can stop. App blocking and daily time limits also require the child device's Accessibility and Usage access permissions. On Android 13+, sideloaded installs may require **App info → ⋮ → Allow restricted settings** before enabling them.

For email confirmation links to return to the Parent app, add
`io.supabase.familyguard://login-callback/` to **Supabase Dashboard → Authentication → URL Configuration → Redirect URLs**.
The Parent app requests this callback during signup and handles it as an Android deep link.

If running without a configured Supabase backend, local demo accounts are stored on that device and do not sync between separate phones. The local pair code is `1234`.

```bash
# Terminal 1: Run Parent App
cd apps/parent
flutter run

# Terminal 2: Run Child App (on another device or emulator)
cd apps/child
flutter run
```

---

## Connecting a different Supabase project

The APKs include a Supabase project URL and publishable key. You can use your own project in any of these ways:

### 1. Build-time configuration

The Parent dashboard keeps backend details out of its interface. To connect a build to another project, pass its URL and publishable key at build time:

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY
```

The current Android release variant uses the debug signing certificate. Its release-mode APK can be sideloaded for testing, but it is not ready for Play Store publishing; configure a private release keystore before distribution and keep its credentials out of source control.

### 2. In Code (`packages/shared/lib/src/config.dart`)
Replace the configured project values:
```dart
class SupabaseConfig {
  static const String defaultUrl = 'https://YOUR_PROJECT.supabase.co';
  static const String defaultAnonKey = 'YOUR_ANON_KEY';
  ...
}
```

### 3. Via Build Environment Flags
```bash
flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co --dart-define=SUPABASE_ANON_KEY=your_key
```

---

## Supabase setup

For a new project, run [supabase/schema.sql](supabase/schema.sql), then apply the timestamped migrations below in order. Existing projects should apply only migrations that have not already been applied:

1. [Parent-managed child accounts](supabase/migrations/202610150001_parent_managed_child_accounts.sql)
2. [Usage limits and protection requests](supabase/migrations/202610160001_usage_limits_and_protection_requests.sql)
3. [Parent-authorized protection codes](supabase/migrations/202610160002_parent_authorized_protection_codes.sql)
4. [Child device status and push](supabase/migrations/202610170001_child_device_status_and_push.sql)
5. [Location, zones, tasks, moods, insights, and rewards](supabase/migrations/202610170002_location_insights_tasks_and_mood.sql)
6. [Realtime child location updates](supabase/migrations/202610200001_child_location_realtime.sql)
7. [Activity categories, fair-trade suggestions, and mood insight flags](supabase/migrations/202610210001_rules_based_insights_and_trades.sql)
8. [Location-sharing status alerts](supabase/migrations/202610210002_location_sharing_alerts.sql)
9. [Task and homework categories](supabase/migrations/202610210003_task_categories.sql)
10. [Child-specific rules and app categories](supabase/migrations/202610220001_child_scoped_rules.sql)
11. [Child-specific app unlocks and activity scoring](supabase/migrations/202610220002_child_scoped_rewards_and_scoring.sql)

The location, zones, tasks, moods, insights, and rewards migration adds child-opt-in location sharing and family zones, app restrictions within configured zones, parent-assigned tasks with private photo proof, mood check-ins, app activity categories, a computed weekly trust/insight summary, and task streak points. Task photos are stored in the private `task-proof` bucket. Location sharing is off by default; the child must turn it on and grant Android's "Allow all the time" location permission for background updates. When enabled, the child app sends an initial location immediately and refreshes periodically while showing a persistent Android notification. The parent's child-monitoring screen uses an interactive OpenStreetMap view with recent movement, location accuracy, known-place radii, and animated location marker. New known places default to 550 m, with 500 m and 600 m options. Arrival/exit events appear in the Parent alerts view and are sent as push notifications when Firebase is configured. Assigned tasks have their own Parent page, reachable from the child's monitoring screen. The app-activity view graphs the last seven days. New location rows trigger best-effort deletion of that child's records older than 30 days. Android still requires the child device's user to manually grant Usage access and Accessibility access; the app cannot bypass Android's restricted-settings approval.

The latest migration standardizes activity profiling into educational, creative, social, entertainment, and unproductive categories, mapping legacy category values onto the new set. Weekly insights are generated when the parent first opens Plans & Insights that week, include the category breakdown and trust score, and update a supportive mood flag in real time for repeated low/stressed check-ins, especially when they coincide with off-task app events. Extra-time requests receive a transparent, deterministic fair-trade suggestion in the parent review screen. Approved task streaks grant scaling extra-time credits and one 15-minute unlock credit for every seventh approved task; children can redeem an unlock for a parent-blocked app. Trust score incorporates focus activity, task approvals, and consecutive approved tasks, and remains subject to the parent's autonomy threshold. These suggestions, classification, and rewards are rule-based; they do not send a child's activity or mood data to an AI provider.

Parent-assigned work is categorized as a task or homework, can include a due date, and is grouped by date in both Parent and Child views. Apply migration 9 before creating categorized tasks in an existing Supabase project.

Website protection operates on DNS hostnames, not page contents. The configured adult list and parent-defined domain/category rules are enforced by the Child VPN; this rules-only configuration does not provide AI inspection of page text, images, or video.

#### Tamper alert setup

Tamper status is reported by the Child app while it is running and synchronized through Supabase Realtime. The Parent app shows foreground alerts and a recent alert history. Push notifications when the Parent app is closed additionally require Firebase Cloud Messaging:

1. Register the Parent Android app (`com.familyguard.parent`) in a Firebase project and enable Firebase Cloud Messaging.
2. Build the Parent app with that Firebase project's values:
   ```bash
   flutter build apk --release \
     --dart-define=FIREBASE_API_KEY=YOUR_API_KEY \
     --dart-define=FIREBASE_APP_ID=YOUR_ANDROID_APP_ID \
     --dart-define=FIREBASE_PROJECT_ID=YOUR_PROJECT_ID \
     --dart-define=FIREBASE_MESSAGING_SENDER_ID=YOUR_SENDER_ID
   ```
3. Store the Firebase service-account JSON as the `FCM_SERVICE_ACCOUNT` Supabase secret. Never put the service-account JSON in either app or commit it.
4. Deploy the edge function:
   ```bash
   supabase functions deploy send-tamper-alert
   ```

The Parent app must be granted Android notification permission and signed in to register its device token. The `send-tamper-alert` Edge Function also dispatches focus-zone off-task alerts and VPN/monitoring restoration confirmations. Realtime alerts appear in the Parent app while it is open; push alerts require the configured Firebase service account and registered device token. The Child app reports VPN/permission changes on app resume and while active; Android may suspend or terminate apps, so remote alerts cannot be guaranteed if the Child app is force-stopped, offline, or unable to run.

The configured `childguard` project already has the `create-child-account` Edge Function deployed. For a different Supabase project, deploy it from this repository:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy create-child-account
```

The function checks the signed-in user's parent role, creates the child Auth account with the server-only service key, and links it to the parent's family. Never put the service-role key in either APK.

### Database Schema Overview:
- `profiles`: User profile linked to `auth.users` with role (`parent` or `child`).
- `families`: Family entity owned by the parent.
- `family_members`: Links children to families.
- `pair_codes`: Time-limited 6-digit codes for pairing child devices.
- `block_list`: Custom blocked domains set by parent (`family_id`, `domain`, `created_at`).
- `blocked_categories`: Category-based filter rules (`family_id`, `category: adult|social|gambling|games|streaming|violence`).
- `blocked_apps`: Blocked Android application packages (`family_id`, `package_name`, `app_label`).
- `domain_logs`: Live network activity recorded by the child DNS VPN (`child_id`, `family_id`, `domain`, `action: allowed|blocked`, `occurred_at`).
- `app_usage_logs`: Foreground application usage times reported by the child device.
- `app_time_limits`: Per-child, per-package daily usage thresholds in seconds.
- `extra_time_requests`: Child requests for additional app time, with parent approval status and granted minutes.
- `vpn_control_requests`: Child requests to pause protection, with parent approval status.
- `child_locations`, `family_zones`, `zone_app_rules`, `zone_events`: Opt-in location sharing, geofences, and zone-based app restrictions and alerts.
- `child_tasks`, `task_submissions`, `child_streaks`, `child_reward_ledger`: Parent-assigned tasks, private proof, review, points, and streak bonuses.
- `child_mood_checkins`, `child_app_categories`, `child_weekly_insights`: Mood check-ins, app activity categories, and parent-generated weekly summaries/trust scores.
- **Supabase Realtime**: Active on activity logs, child locations, filtering rules, `app_time_limits`, approval requests, and zone activity for live sync between parent controls and child devices.

The parent and child apps include screens for per-app daily limits, extra-time approvals, and VPN pause requests. Daily limits are checked against Android's per-day Usage Access data by the child Accessibility Service, which resets at local midnight; app usage and DNS events are queued locally and synced when the child app can reach Supabase. Parents see pending requests while viewing a child's activity, with an in-app alert when new requests arrive. This project has no push-notification provider configured, so it cannot notify the parent when their app is closed.

### Feature readiness and setup

The Parent dashboard includes a **Family setup** checklist for child accounts, cloud sync, push setup, and child-device permissions. Features that depend on Android permissions or child consent are intentionally not enabled silently:

- **Protection VPN and DNS filtering:** grant the child's VPN consent and enable Android's Always-on VPN in system settings. Website filtering works on DNS hostnames; it does not inspect page contents.
- **App blocking and daily limits:** grant Usage access and Accessibility access on the child's device. The Parent app cannot grant these Android permissions remotely.
- **Location and geofences:** the child must enable location sharing in their app and grant the required background location permission. Parents can then configure known places and zone rules.
- **Push notifications while Parent is closed:** configure Firebase values in the Parent build, register the Parent device, configure the `FCM_SERVICE_ACCOUNT` Supabase secret, and deploy `send-tamper-alert`. Without this, alerts are available in-app while Parent is running.
- **Tasks, homework, proof review, mood check-ins, activity categories, trust insights, and rewards:** these are available when the listed Supabase schema/migrations are applied and the child device is syncing.

The current project does **not** include in-app audio/video calling or AI-based webpage/content classification. Activity categories and weekly insights are rules-based; website filtering is DNS-based. These features need separate implementation and, for calls, a calling/signaling provider before they can be enabled.

For boot recovery, the child app stores its latest rules privately and registers a boot receiver. On the child's device, turn on **Always-on VPN** in Android VPN settings (the app provides a shortcut) after granting VPN consent. Depending on the Android/OEM version, Android may restrict starting VPN services during boot, and a parent app cannot stop a child from changing system VPN settings, revoking VPN/accessibility/usage permissions, force-stopping, or uninstalling the app. Stronger tamper resistance requires a parent-managed, device-owner/MDM provisioning flow; this ordinary app cannot enforce it.

The VPN filters DNS queries it receives (currently IPv4 UDP port 53) and records queried domains, not full URLs or page contents. Encrypted DNS/DoH, DNS-over-TLS, hard-coded resolvers, and other traffic that bypasses the system DNS path are not inspected. The curated category domain lists are not a guarantee of blocking every adult or inappropriate site.

---

## 📱 Features & Workflow

### 1. Parent and child accounts
1. The parent creates their account in **Parent App** and signs in.
2. The parent uses **Create child** on the dashboard to register the child and set a password.
3. The child signs in to **Child App** with those credentials. The account is linked to the parent's family automatically.
4. Child accounts are created and linked by the parent; there is no child self-signup or child-visible pairing-code flow.

### 2. Category-Based Filtering
Parent can toggle curated categories in **Website Filtering -> Categories**:
- **Adult content**: Pornography & adult websites.
- **Social media**: TikTok, Instagram, Snapchat, X, Reddit, Discord, Facebook.
- **Gambling**: Online betting and casino platforms.
- **Games**: Roblox, Minecraft, Epic Games, Steam, Fortnite.
- **Streaming**: YouTube, Twitch, Netflix, Hulu, Disney+.
- **Violence**: Graphic and violent web content.

All category selections are stored in Supabase (`blocked_categories`) and instantly pushed to the child device via Supabase Realtime.

### 3. Specific Domain Filtering
- In **Website Filtering -> Custom Domains**, parent can add any domain (e.g., `reddit.com`, `badsite.org`).
- Rules are saved to Supabase `block_list`.
- Child app combines active category domains with custom blocklist domains and updates the local DNS filter.

### 4. Child Network Activity Monitoring & One-Tap Blocking
- Child enables **Protection ON** (local DNS VPN).
- Every DNS lookup is intercepted on the device:
  - If domain matches blocklist or active categories: returns `NXDOMAIN` (blocked).
  - If allowed: resolves via upstream DNS (`8.8.8.8`).
  - Broadcasts event to Child Flutter app -> uploaded to Supabase `domain_logs`.
- In **Parent App -> Child Device**:
  - Live activity feed shows visited domains with timestamps and Allowed/Blocked status badges.
  - Search and filter by *All*, *Allowed*, or *Blocked*.
  - **One-Tap Block**: Tap the red **Block** button next to any visited domain to instantly add it to the blocklist and enforce it across child devices!

### 5. App Blocking & Usage Monitoring
- Child grants **Usage Access** and **Accessibility Service** permissions.
- Parent can block apps from presets (YouTube, TikTok, Instagram, Discord, Roblox, etc.) or add custom Android package names in **Blocked Apps**.
- Enforced on device via Android `AppBlockAccessibilityService`.
