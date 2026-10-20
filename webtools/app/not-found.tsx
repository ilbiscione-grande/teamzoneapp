import Link from "next/link";

export default function NotFound() {
  return (
    <div className="wt-wrap wt-section wt-narrow">
      <h1 className="wt-page-title">Sidan finns inte</h1>
      <p>Adressen leder inte till någon sida i Webtools.</p>
      <Link className="wt-link" href="/">Till alla appar</Link>
    </div>
  );
}
