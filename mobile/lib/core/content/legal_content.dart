/// Text for the Account information pages. Plain statements of what the app and
/// backend actually do. The Clinician Terms and the Data Processing Agreement are
/// beta drafts until the data-protection lawyer's review (Phase 4); replace them
/// here, and bump [AppConfig.consentVersion], when the reviewed versions are ready.
library;

/// Where clinicians write to about safety, privacy or their data.
const kSafetyEmail = 'saas.ai.yk@gmail.com';

const kDraftNotice =
    'Beta draft, under legal review. This summary describes how the beta works today. '
    'The reviewed version will replace it, and you will be asked to accept it again.';

class InfoSection {
  const InfoSection(this.heading, this.points);

  final String heading;
  final List<String> points;
}

class InfoDoc {
  const InfoDoc({required this.title, required this.intro, required this.sections, this.draft = false});

  final String title;
  final String intro;
  final List<InfoSection> sections;
  final bool draft;
}

const kPrivacyDoc = InfoDoc(
  title: 'How we protect client data',
  intro: 'Your Counselor is built so that client identities never leave your phone.',
  sections: [
    InfoSection('On your phone', [
      'Before anything is sent, the app removes names, phone numbers, email addresses, ID numbers and '
          'similar identifiers, and shows you what it removed.',
      'Send stays locked until you confirm the case contains no identifiers.',
      'Case text and replies are kept in memory only, never saved to the phone, and are wiped when you sign out.',
      'On Android, screenshots and screen recording are blocked on case screens. On iPhone, the app is '
          'blurred in the app switcher.',
      'Phone backups are off for the app, and no crash-reporting or analytics tools are used.',
    ]),
    InfoSection('On our server', [
      'The server checks the text for identifiers again and refuses it if any are found.',
      'When identifiers are caught, only their type and count are recorded (for example "1 phone number"), '
          'never the value.',
      'The server runs on Google Cloud in Mumbai. Passwords and service keys are kept in a secrets vault, '
          'never in the app.',
    ]),
    InfoSection('The AI and other services', [
      'The de-identified case text is sent to one AI provider to write the reply: Anthropic (the Claude '
          'model) or Google (the Gemini model). Our administrators choose which one from an approved list. '
          'Both process the text outside India. If you add your own Anthropic key, your reports go to '
          'Anthropic under your own account.',
      'For diagnostic codes, short search terms (such as a condition name) are sent to the World Health '
          "Organization's ICD-11 service. Case text is not sent.",
      'Every reply passes an automatic safety check before it reaches you.',
      'Payments are handled by Razorpay. Your card, UPI or bank details go to Razorpay only; we keep the '
          'plan, amount and payment status.',
    ]),
    InfoSection('Clients who book with you', [
      'If you use online booking, a client gives their first name and email address and picks a time on your '
          'booking page. Nothing else is asked.',
      'These details are stored encrypted, used only for that appointment and its emails, and deleted 90 days '
          'after the appointment. They are never sent to the AI.',
      'A client can cancel with the link in their confirmation email, or write to us to have their details '
          'deleted sooner.',
    ]),
    InfoSection('What is kept, and who can see it', [
      'Your consults (de-identified text and replies) are stored so you can see them in History.',
      'Only you can see your consults. A small number of administrators can open them for safety review, '
          'and every such view is recorded.',
      '"Delete" in History hides a consult from you; the de-identified copy is kept for safety review '
          'until the retention period ends.',
      'The beta retention period is 12 months, except for open safety reports.',
      'Account → Delete account deletes your sign-in and personal details for good.',
    ]),
  ],
);

const kTermsDoc = InfoDoc(
  title: 'Clinician Terms',
  intro: 'Your Counselor is a consultation aid for registered mental-health professionals.',
  draft: true,
  sections: [
    InfoSection('Who can use it', [
      'Counsellors, trainees, psychologists and psychiatrists who give accurate registration details.',
      'Access starts only after your registration has been verified. Your access level is set by us, '
          'based on that verification.',
      'Your account is for you alone. Do not share your sign-in.',
    ]),
    InfoSection('Your responsibilities', [
      'Never enter information that could identify a client: names, contact details, ID numbers, '
          'addresses, or rare details that point to one person.',
      'You stay responsible for every clinical decision. Check every reply against your own judgement '
          'before using it.',
      'If a client may be at risk, follow your crisis protocol and contact emergency services. '
          'Do not rely on the app.',
      'Use "Report a problem" when a reply looks wrong or unsafe.',
    ]),
    InfoSection('What the service does', [
      'Replies are generated by AI and checked automatically before you see them. A reply may still '
          'be incomplete or wrong.',
      'There is a daily limit on consults per clinician.',
      'During the beta, features may change, and the service may be paused or withdrawn.',
    ]),
  ],
);

const kDpaDoc = InfoDoc(
  title: 'Data Processing Agreement',
  intro: 'How de-identified case information you send is processed on your behalf.',
  draft: true,
  sections: [
    InfoSection('What is processed', [
      'Your account details: name, gender, age, email address, role, registration body and number, and the date '
          'you accepted these terms. These are about you, never a client, and are not sent to the AI.',
      'If you use online booking: each client\'s first name, email address and appointment time, which they '
          'enter on your booking page. These are stored encrypted, are not sent to the AI, and are deleted 90 '
          'days after the appointment.',
      'Payments: plan, amount and status (card, UPI and bank details stay with Razorpay). Your own AI key, if '
          'you add one: stored encrypted and never shown again.',
      'De-identified case text you send, the replies, safety-check results and usage figures.',
      'Problem reports you send, and the types of any identifiers that were caught.',
    ]),
    InfoSection('Why', [
      'Only to provide the consultation service, keep it safe, review reported problems, verify clinicians, '
          'take payments and manage appointments. The data is not sold and is not used for advertising.',
    ]),
    InfoSection('Where, and by whom', [
      'Google Cloud (Mumbai): runs the server.',
      'Supabase: database and email sign-in.',
      'Anthropic (the Claude model) or Google (the Gemini model): one of them, chosen by our administrators, '
          'writes the replies. Each processes de-identified text only, outside India.',
      'Razorpay: payments.',
      'Our email service: booking confirmations and reminders to clients.',
      'World Health Organization ICD-11 service: receives short diagnostic search terms only.',
    ]),
    InfoSection('Safeguards', [
      'Identifiers are removed on the phone and checked again on the server.',
      'Data is encrypted in transit. Clients\' booking details and AI keys are also encrypted at rest. Service '
          'keys are kept in a secrets vault.',
      'Administrator access to consults is recorded.',
      'The beta retention period is 12 months for consults, except for open safety reports, and 90 days after '
          'the appointment for client booking details.',
    ]),
    InfoSection('Your requests', [
      'To delete your account, use Account → Delete account in the app. Your sign-in and personal details are '
          'deleted straight away; payment records stay as tax law requires, and de-identified consults stay '
          'until the retention period ends.',
      'To ask about your data, or if you can no longer open the app, email $kSafetyEmail.',
    ]),
  ],
);
