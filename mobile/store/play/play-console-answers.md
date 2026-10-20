# Play Console: answers for every form

Fill these in Play Console → your app → **Policy and programs → App content** (and the store listing pages). Each answer describes what the app does today; check it again if the app changes.

## Before you submit: three things to sort out
1. **Payments policy (most important).** The app sells digital content (Learn, Practice, BYOK Scale and Scale plans, single reports, single prints of Knowledge pages) through Razorpay. Google Play normally requires Google Play Billing for digital content. In India, Google allows other payment systems only through its **user choice / alternative billing programme**, which has its own sign-up, fees and on-screen rules. Before the first release, check the current Payments policy in Play Console and either enrol in that programme or switch these purchases to Google Play Billing. Otherwise the app may be rejected.
2. **Account deletion.** Done: **Account → Delete account** in the app (also on the "We're verifying you"
   screen), and a web page at `https://app.yourcounselor.in/delete-account`. Enter that URL in Play Console →
   App content → **Data deletion**. Run migration 011 first (docs/DEPLOY.md).
3. **Reviewer sign-in.** Done in the app: a fixed 6-digit code for one reviewer email only. Set up the account as in App access below.

## App access (reviewer sign-in)
Google's reviewers can't receive the emailed code, so one account has a **fixed 6-digit code** instead. The
reviewer uses the same screens as everyone else (email → code). For **playreview@yourcounselor.in** only
(`REVIEW_EMAIL` in `mobile/config/live.json`) no email is sent, and the code is checked against that account's
password in Supabase. Every other email still gets a new emailed code. The code is never in the app or in git.

Set it up once:
1. **Supabase** → Authentication → Users → **Add user** → *Create new user*: email `playreview@yourcounselor.in`,
   password: **the fixed 6-digit code you choose** (for example a random 6-digit number), tick **Auto Confirm User**.
2. **On your phone** (new app build): Sign in → that email → **Send code** → type the 6-digit code → Verify. Fill in
   the registration (name "Google Play Reviewer", role Psychologist, registration body RCI, number "PLAY-REVIEW").
3. **/admin → Registrations**: verify the account (level **L2**).
4. **/admin → Subscriptions & Users** → the reviewer → **Give a plan…** → **Scale** for 90 days (it brings 10
   AI-Guided reports a month), plus **Adjust credits** +5 for quick consults, so reviews can use every part of
   the app even while charging is on.
5. **Play Console → App content → App access** → *All or some functionality is restricted* → add instructions:
   > YourCounselor is for registered mental-health professionals. Enter the email below and tap Send code (no email
   > is sent to this account), then enter the code below. The account is verified and on the Scale plan.
   > Email: playreview@yourcounselor.in · Code: [your 6-digit code]

To change the code, change the password in Supabase (and in Play Console). To end reviewer access, delete the
user in Supabase or deactivate the account in /admin. Keep the account's credits small: anyone who learns the
email and code can sign in as the reviewer.

## Ads
- **Does your app contain ads?** No.

## Content rating (IARC questionnaire)
- Category: **Reference, News, or Educational** (a medical reference app for professionals).
- Violence, sexual content, profanity, gambling: **No**.
- Controlled substances: the clinical reference text discusses substance use as a clinical topic only. Answer **No** to promoting or depicting use; mention educational references if asked.
- Suicide and self-harm: the app discusses risk assessment and crisis helplines in a clinical, educational way. Answer accordingly; it does not depict or encourage self-harm.
- User interaction: users don't interact with each other, no chat between users, no sharing of location.
- Digital purchases: **Yes** (plans, single reports, single prints).
- Expect a Teen / 12+ to 16+ rating, depending on the self-harm answers.

## Target audience and content
- Target age: **18 and over** only.
- Appeals to children: **No**.

## News app
- No.

## COVID-19 contact tracing and status
- No.

## Data safety
Encryption in transit: **Yes** (HTTPS everywhere). Users can ask for their data to be deleted: **Yes** (in the app, Account → Delete account, or via the web link above). Payment records and de-identified consults are kept for the periods in the privacy policy. Data is never sold and never used for advertising.

| Data type (Play category) | Collected | Shared | Optional? | Why | Notes |
|---|---|---|---|---|---|
| Personal info → **Name** | Yes | No | Required | Account management, app functionality | Clinician's name. Clients' first names, when the clinician adds an appointment (optional field). |
| Personal info → **Email address** | Yes | No | Required | Account management, app functionality | Sign-in code. Clients' emails for appointment notices (optional field). |
| Personal info → **Other info** | Yes | No | Required | Account management (verification) | Gender, age, professional role, registration body and number. |
| Health and fitness → **Health info** | Yes | No | Required to use consults | App functionality | De-identified case descriptions and the replies. Identifiers are removed on the phone first. |
| Financial info → **Purchase history** | Yes | No | Optional (only if you buy) | App functionality, account management | Plan, amount, payment status. |
| Financial info → **User payment info** | Yes, by the Razorpay SDK in the app | No | Optional (only if you buy) | Payments | Card, UPI and bank details go to Razorpay only; YourCounselor never sees or stores them. |
| App activity, web browsing, location, contacts, photos, files, messages, audio, device or other IDs | No | | | | No analytics, no crash reporting, no advertising ID. |

**Shared** means given to a third party for its own use. Processors acting for YourCounselor (Google Cloud, Supabase, Anthropic or Google for AI replies, Razorpay, the email service) count as service providers, so this data counts as collected but not shared.

## Health apps declaration
- Choose the categories that fit: **Medical reference and education**, and **Clinical decision support** (for healthcare professionals).
- The app is not a regulated medical device, does not diagnose, and is not for patients or the public.

## Financial features
- None. The app does not offer loans, banking, crypto, insurance or other financial services.

## Government apps
- No.

## Store settings
- App category: **Medical**. Tags: Medical reference, Productivity.
- Contact email: a support address you monitor (required). Website: optional.
- Privacy policy URL: a public web page with `privacy-policy.md` (after the lawyer's review).

## Graphics checklist
| Asset | File | Size |
|---|---|---|
| App icon | app-icon-512.png | 512 × 512, 32-bit PNG |
| Feature graphic | feature-graphic-1024x500.png | 1024 × 500 |
| Phone screenshots (8) | screenshots/01–08 | 1080 × 1920 each, in a phone frame |

## Release
- Upload an **Android App Bundle (.aab)** signed for release, not the test APK. Play App Signing keeps the signing key; you keep the upload key, never in git.
- Version: 1.0.0 (build 1). Each upload needs a higher build number.
- Start with **Internal testing**, then Closed testing. New personal developer accounts must run a closed test with at least 12 testers for 14 days before Production.
