import type { Metadata } from "next";
import { LegalDocument } from "../../../components/legal-document";
import { sellerAddress, sellerNumber } from "../../../lib/legal-seller";

export const metadata: Metadata = {
  title: "Terms of use",
  description: "Terms of use for TeamZone.",
  robots: { index: false, follow: false },
};

const sections = [
  {
    title: "1. About TeamZone and the agreement",
    paragraphs: [
      "TeamZone is a digital service for sports clubs, teams, coaches, players, guardians and club officials. These terms govern the use of the service.",
      `Service provider: Tre 60 Grader, sole trader, organisation number ${sellerNumber}, ${sellerAddress}, Sweden.`,
    ],
  },
  {
    title: "2. Account and permissions",
    items: [
      "You must give correct account details and protect your sign-in details.",
      "Access is governed by links to clubs, teams and roles. You may only use permissions that have actually been given to you.",
      "A guardian may act for a child only through a verified relationship in the service.",
      "The club is responsible for keeping its roles, memberships and publishing permissions up to date.",
    ],
  },
  {
    title: "3. Permitted use",
    paragraphs: ["TeamZone may only be used for lawful, sports-related activities."],
    items: [
      "You may not try to get round permission checks or gain access to other users' details.",
      "You may not publish unlawful, offensive or misleading content, or privacy-sensitive content without a legal basis.",
      "You may not disrupt the operation of the service, automate abuse or use protected club names without approval.",
    ],
  },
  {
    title: "4. Content from clubs and users",
    paragraphs: [
      "Whoever adds text, images or other information is responsible for holding the necessary rights and permissions. Ownership of the content does not pass to TeamZone.",
      "You give TeamZone the limited right needed to store, process and show the content within the service, according to your choices and permissions.",
    ],
  },
  {
    title: "5. Minors",
    paragraphs: [
      "Clubs and responsible adults must treat children's details with care and follow the applicable rules, legal bases and consent requirements. Public exposure of minors' details is switched off by default.",
      "You must be at least 13 years old to create an account of your own. Younger children may use TeamZone only through a verified link to a guardian. To buy a subscription you must be 18 or have your guardian's approval.",
    ],
  },
  {
    title: "6. Operation, changes and availability",
    paragraphs: [
      "We work for a secure and available service but cannot guarantee uninterrupted operation. Maintenance, security measures or external services may temporarily affect features.",
      "Material changes to the terms are versioned and require a new explicit approval in the app.",
    ],
  },
  {
    title: "7. Suspension and termination",
    paragraphs: [
      "Access may be restricted in the event of a security risk, suspected abuse or a material breach of the agreement. Users can request account closure and the handling of personal data as set out in the privacy policy. Activity history may need to be kept in anonymised form.",
    ],
  },
  {
    title: "8. Fees and payment",
    paragraphs: [
      "Tacticsboard is sold as a subscription to individuals. Price, free trial, payment, cancellation and the right of withdrawal are set out in the Terms for Tacticsboard, which you accept when you buy.",
      "Fees for clubs are agreed separately with each club.",
    ],
  },
  {
    title: "9. Liability and governing law",
    paragraphs: [
      "TeamZone does not replace professional medical, legal or financial advice. Users and clubs are responsible for the decisions they make in their activities.",
      "Swedish law applies to the terms. As a consumer you can turn to the Swedish National Board for Consumer Disputes (ARN), arn.se, if we cannot agree. Disputes may also be tried by the general courts.",
      "We are liable for damage we have caused intentionally or through gross negligence. Otherwise our liability is limited to what you have paid us in the last 12 months. The limit does not apply to rights you have as a consumer by law.",
    ],
  },
  {
    title: "10. Contact",
    paragraphs: [
      "Send questions about the terms to support@teamzoneapp.se. We reply within two working days.",
    ],
  },
] as const;

export default function EnglishTermsPage() {
  return (
    <LegalDocument
      locale="en"
      eyebrow="Legal"
      title="Terms of use"
      version="2026-11-06"
      updated="6 November 2026"
      counterpart="/villkor"
      introduction="Read the terms before you create or use a TeamZone account."
      sections={sections}
    />
  );
}
