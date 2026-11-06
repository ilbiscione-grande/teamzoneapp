import type { Metadata } from "next";
import { LegalDocument } from "../../../../components/legal-document";
import { sellerAddress, sellerNumber, sellerVat } from "../../../../lib/legal-seller";

export const metadata: Metadata = {
  title: "Terms for Tacticsboard",
  description: "Terms for the Tacticsboard subscription.",
  robots: { index: false, follow: false },
};

const sections = [
  {
    title: "1. The seller and the agreement",
    paragraphs: [
      `Tacticsboard is sold by Tre 60 Grader, sole trader, organisation number ${sellerNumber}, VAT number ${sellerVat}, ${sellerAddress}, Sweden. Email: support@teamzoneapp.se.`,
      "These terms apply when you use Tacticsboard, during the free trial and with a subscription. They apply together with the terms of use for TeamZone. Where the two differ, these terms apply to Tacticsboard.",
    ],
  },
  {
    title: "2. The service",
    paragraphs: [
      "Tacticsboard is a web service where you draw, animate and present tactics and drills. You need an account but no team or club in TeamZone. The service is used in an up-to-date web browser on a computer, tablet or phone.",
    ],
  },
  {
    title: "3. The free trial",
    items: [
      "The free trial lasts 7 days and costs nothing. It starts the first time you open Tacticsboard and is given once per account.",
      "You do not need to give any payment details to try it.",
      "When the free trial ends, Tacticsboard is locked until you subscribe. Nothing you have made is removed.",
    ],
  },
  {
    title: "4. Price and payment",
    items: [
      "The subscription costs SEK 39 per month or SEK 390 per year. The prices include VAT.",
      "Launch offer: if you buy the yearly subscription by 31 December 2026 you get 25% off the first year and pay SEK 292.50. The regular price applies after that.",
      "Payment is handled by Stripe. You pay by card, Apple Pay or Google Pay. We do not see your card details.",
      "If you buy with more than two days of the free trial left, the first payment is taken when the free trial ends. Otherwise it is taken at once.",
      "Receipts are sent by email and are available under Manage payment and receipts on the account page.",
    ],
  },
  {
    title: "5. Renewal and cancellation",
    items: [
      "The subscription renews automatically every month or year until you cancel it.",
      "You can cancel whenever you like under Manage payment and receipts on the account page. The subscription runs until the end of the period and is then not renewed. Payment for a period that has started is not refunded, except on withdrawal under section 6.",
      "If you close your account, the subscription ends at once without a refund, except on withdrawal under section 6.",
      "If a payment fails you have 14 days to update your payment details. Everything works during that time. After that, Tacticsboard is locked until the payment is sorted out. Nothing is removed.",
    ],
  },
  {
    title: "6. Right of withdrawal",
    paragraphs: [
      "If you are a consumer, you have a 14-day right of withdrawal from the day you bought the subscription, under the Swedish Act on Distance Contracts and Off-Premises Contracts.",
      "You withdraw with the Withdraw from purchase button under Subscriptions on the account page. It is there throughout the withdrawal period. You confirm your name and which subscription it concerns, and then confirm that you are withdrawing from the purchase. We immediately send an acknowledgement of receipt by email showing when we received your notice.",
      "You can also email support@teamzoneapp.se within 14 days or use the Swedish Consumer Agency's model withdrawal form. State that you are withdrawing from the purchase and which email address the account has.",
      "When you buy, you ask for the subscription to start at once. If you withdraw, you therefore pay a proportionate part of the price for the time from when the paid period began until you withdrew. Time during the free trial costs nothing. We refund the rest to the same payment method within 14 days of receiving your notice.",
      "The right of withdrawal applies to the purchase of the subscription and not to each automatic renewal. You can always cancel the subscription under section 5.",
    ],
  },
  {
    title: "7. Your content and the library",
    items: [
      "Projects, boards and templates you create are yours. We store and show them only so that the service can work.",
      "If you publish something in the library, other Tacticsboard users can see and copy it. You give them the right to use the copy in their own activities. You can remove what you have published, but copies already made remain.",
      "You are responsible for what you publish. It may not be offensive, unlawful or copied from someone else without permission.",
      "Content in the library can be reported. Support can hide content that breaks the terms.",
      "Players' names are personal data. Do not write out the names of others, especially children, in what you publish or share openly.",
    ],
  },
  {
    title: "8. Shared links and live sessions",
    paragraphs: [
      "Links and folders you have shared keep working even if your subscription ends, until you remove the sharing. Whoever opens a link or joins a live session needs no subscription.",
    ],
  },
  {
    title: "9. Operation and changes",
    items: [
      "We work to keep Tacticsboard running at all times but cannot promise uninterrupted operation. Maintenance and faults at suppliers may temporarily affect the service.",
      "We may change the price or the terms. If a change is to your disadvantage, we tell you by email at least 30 days before it applies to you. A new price applies from your first renewal after that. The price of a period you have already paid for does not change.",
      "If you do not want to continue, cancel the subscription before the change applies. It then ends at the end of the period.",
    ],
  },
  {
    title: "10. Liability",
    paragraphs: [
      "Our liability is limited to what you have paid for Tacticsboard in the last 12 months, except in the case of intent or gross negligence. The limit does not apply to rights you have as a consumer by law.",
      "If the service is faulty, you as a consumer have rights under the Swedish Act on Contracts for the Supply of Digital Content and Digital Services, for example that we correct the fault, that you get a price reduction or that you terminate the contract.",
      "We recommend keeping copies of important projects using the export.",
    ],
  },
  {
    title: "11. Support",
    paragraphs: [
      "Send questions and problems to support@teamzoneapp.se. We reply within two working days.",
    ],
  },
  {
    title: "12. Disputes",
    paragraphs: [
      "Swedish law applies to the agreement. Contact us first if you are unhappy. If we cannot agree, you as a consumer can turn to the Swedish National Board for Consumer Disputes (ARN), arn.se. Disputes may also be tried by the general courts.",
    ],
  },
] as const;

export default function EnglishTacticsboardTermsPage() {
  return (
    <LegalDocument
      locale="en"
      eyebrow="Legal"
      title="Terms for Tacticsboard"
      version="2026-11-06"
      updated="6 November 2026"
      counterpart="/villkor/tacticsboard"
      introduction="This is what applies when you try and subscribe to Tacticsboard: price, payment, cancellation and the right of withdrawal."
      sections={sections}
    />
  );
}
