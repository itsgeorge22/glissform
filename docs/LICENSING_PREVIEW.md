# Licensing development preview — paused

Glissform is fully free to use. `LicenseController.previewsEnabled` is `false`, so both Dev and release launches ignore `--license-preview`. There is no trial countdown, License navigation, checkout, activation requirement or expiry gate. Existing client fixtures remain untouched. The screens, icons, service and tests below are retained for possible reuse.

To resume this **local prototype** after a new product decision, change `previewsEnabled` to `true`, rebuild Dev, and use the steps below. The free-mode regression expectation must change with that decision. This restores the existing UI; it does not enable production payments. Release builds still ignore the flag. The canonical website currently has no checkout or licensing UI to restore.

This is an opt-in local prototype for a **$2.99 one-time license for lifetime access**, a **72-hour free trial**, and **one active Mac per key**. No payment provider is connected. The public beta and normal launches keep their existing access behaviour.

## Run after re-enabling

Build with `bash scripts/build.sh`. Quit any running Glissform Dev instance before opening the preview. Avoid running Dev and release effects together.

In one terminal, start the local service (Python 3.9 or later):

```sh
python3 scripts/license-preview.py
```

In another terminal, open the development app with the preview flag:

```sh
open -a "$PWD/build/Glissform Dev.app" --args --license-preview
```

Only a bundle with `GlissformDeveloperTools` enabled honours this flag. Release builds ignore it. The service listens only on `127.0.0.1:8765`; it is not a hosted service and must never be exposed publicly.

## Try the flow

1. The first preview launch automatically starts the 72-hour trial. It includes time while the app is closed and survives relaunches; an expired trial never restarts.
2. The sidebar shows a remaining-time label (3 days left, then 2 days left; below 24 hours, whole hours such as 23 hours left) in the same container as the Update card. At exactly 24 hours it shows “1 day left”; below an hour it shows “Less than an hour left”, and at expiry “Trial ended”. The trial card uses the supplied Time Circle icon in a green-tinted tile. An available update replaces the trial card. Activating a license hides the trial card. **View license** opens the License page.
3. Choose **Buy for $2.99** on the right of the License status card. A browser opens the local checkout. **Simulate payment** issues a test license and displays it for copying; **Cancel** issues nothing. No card data, money or email is involved. Repeating a completed checkout never creates another license.
4. Paste the key into **License → Activate this Mac**. Reusing a key on the same device is idempotent. Each license allows one active Mac at a time. The local service rejects a second device identity and allows a freed slot to be reused after **Deactivate this Mac**. Multiple physical Macs have not been tested; automated checks simulate their identities against one ledger.
5. When the trial expires, existing and pending animation frames are cleared, input is released and subsequent gestures are blocked. Settings, support, the menu bar, buying and activating remain available. Automated checks exercise expiry without waiting three days; there is no expiry simulation button in the customer interface.
6. Stop the local service to try an activation/deactivation failure. A failed operation preserves existing access. A successfully activated preview can restart offline using its saved local entitlement.

The License page uses the supplied key SVG, green sidebar/page icon surfaces independent of Send feedback’s orange, and feature-card insets (12 points at top/leading/bottom, 24 trailing). The purchase card is titled “Get Glissform”. Its purchase action sits to the right of the title, beside the subtitle “Pay $2.99 once for lifetime access on this Mac.” The page has no manual trial-start action, payment-details footnote or development-preview footer. Checkout itself still clearly identifies simulated payments.

Trial/key state and a random installation ID are stored under `licensePreview.v1` in Glissform Dev's preferences, independently of other settings. The service stores test orders, keys and device slots in ignored `build/license-preview.sqlite3`. No hardware serial number, screenshot or payment details are transmitted. Both client and server data are local development fixtures.

To reset just the client fixture, quit Dev and run `defaults delete com.george.glissform.mvp.dev licensePreview.v1`. This also creates a new installation ID next time; deactivate first if you want to free its server slot. To reset the ledger, stop the server and remove only `build/license-preview.sqlite3`. Existing saved client entitlements must then be reset separately. A normal Dev launch without the flag does not enforce the preview gate.

## Production boundary

`LicenseService` separates the native flow from checkout/activation transport. The production replacement must use a hosted licensing backend: a payment provider supplies checkout and authenticated payment notifications; the backend verifies the settled amount, currency and product, handles retries idempotently, issues a license and delivers it to the buyer. A browser success redirect must never be proof of payment.

Before enabling a public paywall, implement HTTPS, signed device-bound entitlements, an explicit offline/grace policy, server-owned trial eligibility, protected local storage, stable device/reinstallation rules, account or key recovery, lost-device slot management, refund/revocation handling and abuse controls. The current preferences and randomly generated installation ID can be reset or copied and are **not production license protection**. Clock rollback is only clamped to the last observed local time. Cached preview activations do not discover later server revocation.

The provider, fees, seller eligibility, minimum purchase amount and payouts remain unresolved. No provider has been selected, and none of this work establishes that $2.99 payments can be processed. Production purchase receipts/key delivery, customer terms, licensing privacy text, distribution and the physical multi-Mac experience remain pending.

## Verification

The free-mode change on 2026-10-03 passed the Dev build and full local suite, including default-controller access with expired saved state, ignored preview shortcuts, inactive commerce methods and fixture preservation. A fresh Dev launch showed normal Seamless Close settings with no License navigation or trial card. The old local checkout server was stopped. The canonical website build and 12 content/deployment checks passed; its browser preview showed free download labels and the free-availability FAQ. This verification preceded publication. Source and website publication were subsequently authorized on 2026-10-03; no new app release is included. GitHub metadata/release review could not be completed because the GitHub CLI is unavailable in this environment.

`bash scripts/test.sh` includes Swift trial/controller checks and Python checkout/activation tests. The app lifecycle checks also cover access loss during a pending capture, a visible effect and a retained sleep frame. Automated checks do not establish physical lid timing, normal system sleep on new hardware, international card acceptance or real payouts.

On 2026-10-03, the Dev build and full local suite passed. The initial native UI walkthrough verified the former manual trial start and expiry, Safari checkout, copying a displayed test key into activation, and deactivation returning an expired trial to the paywall. Safari required same-origin referrer metadata for the form POST; the final policy preserves that metadata locally and omits it for external destinations. This is development verification, not a published release or real payment trial.

The revised first-launch flow passed the Dev build, full local regression suite and focused persistence checks. The native preview was checked for its automatic trial, live sidebar countdown, supplied SVG, green icon surfaces, right-aligned purchase action and removed footnotes. Update-card precedence is implemented in the shared sidebar branch; a real update notification was not exercised in this Dev preview.
