import { Suspense } from "react";
import { SignIn } from "../../components/sign-in";

export const metadata = { title: "Logga in" };

export default function SignInPage() {
  return (
    <div className="wt-wrap wt-section wt-narrow">
      <Suspense fallback={<p className="wt-status">Laddar…</p>}>
        <SignIn />
      </Suspense>
    </div>
  );
}
