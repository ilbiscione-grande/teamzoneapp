import type { Metadata } from "next";
import { SurveyForm } from "../../../components/survey-form";
import { surveySender, validSurveyToken } from "../../../lib/survey";
import { loadPublicSurvey } from "../../../lib/survey-server";
import "../survey.css";

// Answers may have changed since the page was last read.
export const dynamic = "force-dynamic";

type Props = { params: Promise<{ token: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { token } = await params;
  const survey = validSurveyToken(token) ? await loadPublicSurvey(token) : null;
  return { title: survey?.title ?? "Enkät", robots: { index: false, follow: false } };
}

/** A team's survey: answered without an account, by personal or open link. */
export default async function SurveyPage({ params }: Props) {
  const { token } = await params;
  const survey = validSurveyToken(token) ? await loadPublicSurvey(token) : null;
  if (!survey) {
    return (
      <div className="wt-wrap wt-section sv-page">
        <p className="wt-kicker dark">Enkät</p>
        <h1 className="wt-page-title">Enkäten hittades inte</h1>
        <p>Länken kan vara fel, eller så har ledarna tagit bort enkäten. Fråga dina ledare om en ny länk.</p>
      </div>
    );
  }
  const sender = surveySender(survey);
  return (
    <div className="wt-wrap wt-section sv-page">
      <p className="wt-kicker dark">{sender || "Enkät"}</p>
      <h1 className="wt-page-title">{survey.title}</h1>
      {survey.person_name && <p className="sv-for">Till {survey.person_name}</p>}
      {survey.intro && <p className="sv-intro">{survey.intro}</p>}
      <SurveyForm token={token} survey={survey} />
    </div>
  );
}
