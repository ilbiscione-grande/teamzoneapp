import { Suspense } from "react";
import { SignIn } from "../../components/sign-in";
import { serverT } from "../../lib/i18n/server";

export async function generateMetadata() {
  return { title: (await serverT())("Logga in") };
}

export default async function SignInPage() {
  const t = await serverT();
  return (
    <div className="wt-wrap wt-section wt-narrow">
      <Suspense fallback={<p className="wt-status">{t("Laddar…")}</p>}>
        <SignIn />
      </Suspense>
    </div>
  );
}
