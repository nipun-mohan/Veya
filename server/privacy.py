"""Public legal pages for Veya."""

PRIVACY_POLICY_HTML = r'''<!doctype html>
<html lang="en"><head><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Veya Privacy Policy</title><style>
:root{--ink:#230843;--orange:#ff8a20;--paper:#fffaf2;--muted:#655d6e;--line:#eadfd2}*{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font-family:Inter,ui-sans-serif,system-ui,-apple-system,sans-serif;line-height:1.62}.wrap{max-width:800px;margin:auto;padding:54px 24px 84px}.brand{display:flex;gap:11px;align-items:center;font-size:20px;font-weight:850;letter-spacing:-.04em}.mark{width:34px;height:34px;border-radius:11px;background:var(--orange);display:grid;place-items:center}.mark svg{width:24px}h1{font-size:44px;line-height:1.05;letter-spacing:-.055em;margin:64px 0 10px}h2{font-size:21px;letter-spacing:-.025em;margin:40px 0 8px}p,li{font-size:16px;color:#31263d}.date,.note{color:var(--muted);font-size:14px}.note{background:#fff1df;border-left:4px solid var(--orange);padding:14px 16px;border-radius:0 12px 12px 0}a{color:#8b3b00;font-weight:700}ul{padding-left:22px}footer{margin-top:52px;padding-top:20px;border-top:1px solid var(--line);color:var(--muted);font-size:14px}@media(max-width:520px){.wrap{padding:36px 20px 60px}h1{font-size:36px;margin-top:46px}}
</style></head><body><main class="wrap"><div class="brand"><span class="mark"><svg viewBox="0 0 100 100" aria-hidden="true"><g stroke="#230843" stroke-width="13" stroke-linecap="round"><path d="M16 28v36"/><path d="M33 42v36"/><path d="M50 56v36"/><path d="M67 42v36"/><path d="M84 28v36"/></g></svg></span>veya</div>
<h1>Privacy Policy</h1><p class="date">Effective date: 29 September 2026</p>
<p>This Privacy Policy explains how Veya handles information when you use its voice transcription, translation, and floating-assistant features.</p>
<p class="note">Veya is designed to process your voice and text only when you choose to use its recording or translation features. It does not sell your personal information or use it for advertising.</p>

<h2>Information we handle</h2><ul><li><strong>Phone number and authentication data.</strong> We use your phone number to verify your account. Your number is stored on your device in encrypted storage and processed only to provide verification and account access.</li><li><strong>Voice recordings and generated text.</strong> When you start a recording, Veya securely processes the audio to transcribe, translate, and create the selected writing style. Veya processes these requests in memory and does not retain recordings or generated messages after processing.</li><li><strong>Selected language and app preferences.</strong> Your speaking language, chosen apps, floating-icon preferences, and onboarding choices are stored locally on your device.</li><li><strong>Accessibility information.</strong> If you enable the floating assistant, Veya uses Android's Accessibility Service only to determine whether a selected app has an active, editable, non-password message field, so it can show the assistant and insert text when you request it. Veya does not use Accessibility Service access to collect passwords or to read, sell, or build profiles from your messages.</li><li><strong>Technical and security information.</strong> Veya may process limited request and error metadata to operate, secure, and improve reliability of the service.</li></ul>

<h2>How we use information</h2><p>We use this information only to verify your account, provide transcription and translation, insert or copy the message you select, maintain your settings, prevent abuse, and operate and secure Veya.</p>

<h2>Your choices</h2><ul><li>You can decline or revoke microphone and Accessibility Service permissions in Android Settings. Without them, the related feature will not work.</li><li>You can change your language and selected-app preferences in Veya.</li><li>You can request deletion of your account-related information by contacting us.</li></ul>

<h2>Security</h2><p>Veya uses encrypted network connections and keeps service credentials outside the app. No method of transmission or storage is completely secure, but we use reasonable safeguards appropriate to the service.</p>

<h2>Children</h2><p>Veya is not directed to children under 13 and we do not knowingly collect personal information from children.</p>

<h2>Changes to this policy</h2><p>We may update this policy when Veya changes. The current version and effective date will always be available on this page.</p>

<h2>Contact</h2><p>For privacy questions or data-deletion requests, contact <a href="mailto:nipun@heyveya.app">nipun@heyveya.app</a>.</p>
<footer><a href="/terms">Terms of Service</a> &nbsp;·&nbsp; © 2026 Veya</footer></main></body></html>'''

TERMS_OF_SERVICE_HTML = r'''<!doctype html>
<html lang="en"><head><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Veya Terms of Service</title><style>
:root{--ink:#230843;--orange:#ff8a20;--paper:#fffaf2;--muted:#655d6e;--line:#eadfd2}*{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font-family:Inter,ui-sans-serif,system-ui,-apple-system,sans-serif;line-height:1.62}.wrap{max-width:800px;margin:auto;padding:54px 24px 84px}.brand{display:flex;gap:11px;align-items:center;font-size:20px;font-weight:850;letter-spacing:-.04em}.mark{width:34px;height:34px;border-radius:11px;background:var(--orange);display:grid;place-items:center}.mark svg{width:24px}h1{font-size:44px;line-height:1.05;letter-spacing:-.055em;margin:64px 0 10px}h2{font-size:21px;letter-spacing:-.025em;margin:40px 0 8px}p,li{font-size:16px;color:#31263d}.date,.note{color:var(--muted);font-size:14px}.note{background:#fff1df;border-left:4px solid var(--orange);padding:14px 16px;border-radius:0 12px 12px 0}a{color:#8b3b00;font-weight:700}ul{padding-left:22px}footer{margin-top:52px;padding-top:20px;border-top:1px solid var(--line);color:var(--muted);font-size:14px}@media(max-width:520px){.wrap{padding:36px 20px 60px}h1{font-size:36px;margin-top:46px}}
</style></head><body><main class="wrap"><div class="brand"><span class="mark"><svg viewBox="0 0 100 100" aria-hidden="true"><g stroke="#230843" stroke-width="13" stroke-linecap="round"><path d="M16 28v36"/><path d="M33 42v36"/><path d="M50 56v36"/><path d="M67 42v36"/><path d="M84 28v36"/></g></svg></span>veya</div>
<h1>Terms of Service</h1><p class="date">Effective date: 12 November 2026</p>
<p>These Terms of Service govern your use of Veya, including its voice transcription, translation, writing-assistance, and Android floating-assistant features. By creating an account or using Veya, you agree to these Terms and our <a href="/privacy">Privacy Policy</a>.</p>

<h2>Using Veya</h2><p>Veya helps you turn speech into text and refine that text in styles you choose. You are responsible for reviewing generated text before using, sharing, or sending it. Veya does not send messages, make calls, or complete actions in other apps on your behalf.</p><p>The Android floating assistant is optional. When you enable it, Veya may identify the active editable, non-password text field in apps you choose, and inserts text only after you request insertion. You can disable this access at any time in Android Settings.</p>

<h2>Your account and security</h2><p>You must provide accurate information and keep access to your device secure. You are responsible for activity that occurs through your account. Tell us promptly if you believe your account has been used without permission.</p>

<h2>Subscriptions and payments</h2><p>Some Veya features may be offered through a paid subscription. Prices, trial terms, and renewal details are shown before you approve a payment mandate. Unless cancelled before the next billing date, subscriptions renew automatically at the displayed interval. You may cancel a subscription through the payment provider or by contacting us; cancellation stops future renewals and does not automatically refund amounts already paid, except where required by law.</p>

<h2>Acceptable use</h2><p>You may not use Veya to break the law, infringe another person's rights, distribute harmful content, impersonate others, interfere with the service, bypass security controls, or attempt to access another person's account or data. Do not use Veya to process information unless you have the right to do so.</p>

<h2>Service availability and generated content</h2><p>Voice recognition and AI-generated wording can be inaccurate or incomplete. Do not rely on Veya as the sole source for legal, medical, financial, emergency, or other high-stakes decisions. We may change, suspend, or discontinue features when reasonably necessary to operate, secure, or improve the service.</p>

<h2>Intellectual property</h2><p>Veya and its software, branding, and service content are owned by Veya or its licensors. You retain responsibility for the content you submit and the text you choose to use.</p>

<h2>Disclaimers and liability</h2><p>To the extent permitted by law, Veya is provided “as is” and “as available.” We do not guarantee that the service will always be uninterrupted, accurate, or available. We are not liable for indirect, incidental, special, consequential, or punitive damages arising from use of the service. Nothing in these Terms limits rights that cannot be limited under applicable law.</p>

<h2>Changes and termination</h2><p>We may update these Terms when Veya changes or legal requirements change. The current version and effective date will be posted here. You may stop using Veya at any time. We may suspend or terminate access for misuse, security reasons, or legal compliance.</p>

<h2>Contact</h2><p>For questions about these Terms, account deletion, or subscriptions, contact <a href="mailto:nipun@heyveya.app">nipun@heyveya.app</a>.</p>
<footer><a href="/privacy">Privacy Policy</a> &nbsp;·&nbsp; © 2026 Veya</footer></main></body></html>'''

DELETE_ACCOUNT_HTML = r'''<!doctype html>
<html lang="en"><head><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Delete your Veya account</title><style>
:root{--ink:#230843;--orange:#ff8a20;--paper:#fffaf2;--muted:#655d6e;--line:#eadfd2}*{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font-family:Inter,ui-sans-serif,system-ui,-apple-system,sans-serif;line-height:1.62}.wrap{max-width:800px;margin:auto;padding:54px 24px 84px}.brand{display:flex;gap:11px;align-items:center;font-size:20px;font-weight:850;letter-spacing:-.04em}.mark{width:34px;height:34px;border-radius:11px;background:var(--orange);display:grid;place-items:center}.mark svg{width:24px}h1{font-size:44px;line-height:1.05;letter-spacing:-.055em;margin:64px 0 10px}h2{font-size:21px;letter-spacing:-.025em;margin:40px 0 8px}p,li{font-size:16px;color:#31263d}.date,.note{color:var(--muted);font-size:14px}.note{background:#fff1df;border-left:4px solid var(--orange);padding:14px 16px;border-radius:0 12px 12px 0}a{color:#8b3b00;font-weight:700}ul,ol{padding-left:22px}footer{margin-top:52px;padding-top:20px;border-top:1px solid var(--line);color:var(--muted);font-size:14px}@media(max-width:520px){.wrap{padding:36px 20px 60px}h1{font-size:36px;margin-top:46px}}
</style></head><body><main class="wrap"><div class="brand"><span class="mark"><svg viewBox="0 0 100 100" aria-hidden="true"><g stroke="#230843" stroke-width="13" stroke-linecap="round"><path d="M16 28v36"/><path d="M33 42v36"/><path d="M50 56v36"/><path d="M67 42v36"/><path d="M84 28v36"/></g></svg></span>veya</div>
<h1>Delete your Veya account</h1><p class="date">Effective date: 18 November 2026</p>
<p>You can request deletion of your Veya account and account-related data at any time.</p>
<h2>How to request deletion</h2><ol><li>Send an email to <a href="mailto:nipun@heyveya.app?subject=Veya%20account%20deletion%20request">nipun@heyveya.app</a> from, or including, the phone number associated with your Veya account.</li><li>Use the subject line <strong>Veya account deletion request</strong>.</li><li>We may ask you to verify control of the phone number before acting on the request.</li></ol>
<h2>What is deleted</h2><p>After verification, we delete the account record and associated subscription-entitlement information held by Veya. Active payment mandates must be cancelled through the payment provider or by requesting cancellation in the same email.</p>
<h2>What is not retained</h2><p>Veya does not retain voice recordings or generated messages after they are processed. Language, selected-app, and onboarding preferences are stored locally on your device; you can remove them by clearing Veya's app storage or uninstalling the app.</p>
<h2>Retention and legal obligations</h2><p>Limited transaction or security records may be retained only where required by law, to resolve a dispute, or to prevent fraud. These records are not used to provide the deleted account.</p>
<h2>Need help?</h2><p>For privacy questions, contact <a href="mailto:nipun@heyveya.app">nipun@heyveya.app</a>.</p>
<footer><a href="/privacy">Privacy Policy</a> &nbsp;·&nbsp; <a href="/terms">Terms of Service</a> &nbsp;·&nbsp; © 2026 Veya</footer></main></body></html>'''
