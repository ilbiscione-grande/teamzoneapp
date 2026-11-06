import type { Metadata } from "next";
import { LegalDocument } from "../../../components/legal-document";
import { sellerAddress, sellerNumber } from "../../../lib/legal-seller";

export const metadata: Metadata = {
  title: "Privacy policy",
  description: "Privacy policy for TeamZone.",
  robots: { index: false, follow: false },
};

const sections = [
  {
    title: "1. Data controller",
    paragraphs: [
      `For accounts, security, central platform operation and Tacticsboard, Tre 60 Grader, sole trader, organisation number ${sellerNumber}, ${sellerAddress}, Sweden, is the data controller.`,
      "Each club is the data controller for the member, team and activity details the club itself decides over. We process those details on the club's behalf.",
    ],
  },
  {
    title: "2. Data we process",
    items: [
      "Account and profile details, such as name, email, language and authentication status.",
      "Links to clubs, teams, roles and members, and verified guardian relationships.",
      "Events, call-ups, replies, attendance, messages and material added by authorised users.",
      "Support, security and audit details needed for traceability and to combat abuse.",
      "Voluntary settings, such as marketing choices. Marketing is off by default.",
    ],
  },
  {
    title: "3. Purposes and legal basis",
    items: [
      "Providing the account and the agreed features: performance of a contract.",
      "Protecting accounts, preventing abuse and keeping the necessary audit trail: legitimate interest, and legal obligations where applicable.",
      "Administering club and team activities: the basis set by the club responsible.",
      "Selling and administering subscriptions: performance of a contract.",
      "Bookkeeping and receipts: legal obligation under the Swedish Bookkeeping Act.",
      "Answering questions to support: legitimate interest in being able to help you, or performance of a contract when the question concerns your service.",
      "Sending marketing: only after a voluntary choice, which can be withdrawn at any time.",
    ],
  },
  {
    title: "4. Access and sharing",
    paragraphs: [
      "Data is shown according to active links to clubs, teams and roles. TeamZone does not sell personal data. Data may be processed by contracted suppliers for things such as hosting, database, authentication, file handling, email and operational monitoring.",
    ],
    items: [
      "Supabase (Singapore): database, sign-in and files. The data is stored in the EU, for Tacticsboard in Stockholm. Safeguard for access from outside the EU: the EU's standard contractual clauses.",
      "Google Firebase (Google): running the websites in the Netherlands and notifications in the app. Notifications may be processed outside the EU, including in the USA. Safeguard: the EU-US Data Privacy Framework.",
      "Resend (USA): sending email, such as confirmations and notifications. The recipient's address and the content of the email are stored in the USA. Safeguards: the EU's standard contractual clauses and the Data Privacy Framework.",
      "ImprovMX (USA): receives email to support. Email is received and stored temporarily in France and may be forwarded through the USA. Safeguard: the EU's standard contractual clauses.",
      "Google Gmail (Google): the support inbox. Email may be processed outside the EU, including in the USA. Safeguard: the Data Privacy Framework.",
      "Stripe (Ireland): payment for Tacticsboard. Stripe processes the payment on our behalf and is an independent data controller for its own purposes, such as security and fraud prevention. Data may be transferred to the USA and India. Safeguards: the Data Privacy Framework and the EU's standard contractual clauses.",
    ],
  },
  {
    title: "4 a. Tacticsboard",
    items: [
      "We store your projects, boards, templates and folders, what you publish in the library, your shared links and live sessions, and reports you make.",
      "About the subscription we store the dates of the free trial, the subscription's status and period, and a reference to your customer record at Stripe. We store no card details.",
      "Players' names you write on the boards are personal data that you yourself are responsible for.",
      "Receipts and invoices are kept at Stripe for seven years, as the Swedish Bookkeeping Act requires. This applies even if you close your account.",
    ],
  },
  {
    title: "5. Children's personal data",
    paragraphs: [
      "Children's data is protected through data minimisation, role-based access and private default settings. A guardian may act only through a verified relationship. Sensitive development, health or media features are not switched on without a specifically decided policy.",
      "You must be at least 13 years old to create an account of your own. Younger children are handled only through a verified guardian or club. Do not write out children's names on boards or in anything else you share openly.",
    ],
  },
  {
    title: "6. Storage and erasure",
    paragraphs: [
      "Data is not kept for longer than the purpose, the agreement, security or legal requirements demand. Account and membership links can be ended, while necessary activity and audit history may be kept with a neutral or anonymised identity.",
    ],
    items: [
      "Account, project and subscription data: as long as the account exists. If you close the account it is erased. If the account is linked to a club, the erasure is reviewed first.",
      "Receipts, invoices, bookkeeping and withdrawal notices: seven years, as the Swedish Bookkeeping Act requires for the records behind payments and refunds.",
      "Email to support: two years after the matter is closed.",
      "Error and crash logs: 30 days. Performance data: 14 days.",
      "Email logs at Resend: 30 days.",
      "Backups of the database: up to 7 days.",
    ],
  },
  {
    title: "7. Your rights",
    items: [
      "Request access to and rectification of your personal data.",
      "Request erasure or restriction when the conditions are met.",
      "Object to processing based on legitimate interest.",
      "Withdraw voluntary consent without earlier processing becoming unlawful.",
      "Request data portability where that right applies, and lodge a complaint with the Swedish Authority for Privacy Protection (IMY).",
    ],
  },
  {
    title: "8. Security",
    paragraphs: [
      "TeamZone uses, among other things, authentication, least privilege, server validation, isolation between clubs, audit logs and protected administrative functions. No digital service can guarantee absolute security.",
    ],
  },
  {
    title: "9. Cookies and local storage",
    paragraphs: [
      "We use only what the service needs in order to work: your sign-in and your settings, for example in Tacticsboard, are saved in the browser. We use no cookies for analytics or marketing.",
    ],
  },
  {
    title: "10. Contact and changes",
    paragraphs: [
      "Send privacy questions and requests about your rights to support@teamzoneapp.se. We reply within two working days.",
      "Material changes are versioned and may require the user to read and confirm the new version in the app.",
    ],
  },
] as const;

export default function EnglishPrivacyPage() {
  return (
    <LegalDocument
      locale="en"
      eyebrow="Your privacy"
      title="Privacy policy"
      version="2026-11-06"
      updated="6 November 2026"
      counterpart="/integritet"
      introduction="This is how TeamZone processes personal data."
      sections={sections}
    />
  );
}
