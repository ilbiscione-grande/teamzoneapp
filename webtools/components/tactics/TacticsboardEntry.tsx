"use client";

// /tacticsboard: the product page for the signed-out, the app for the
// signed-in. The product page itself is server-rendered and passed in, and it
// shows from the first paint: most who come here are visitors, and they should
// not wait for the account to be read. A browser holding a sign-in says so
// before that, and sees "Laddar…" instead of the product page flashing by.
import { useAccount } from "../account";
import { useT } from "../language";

const remembersSignIn = `try{if(localStorage.getItem("teamzone-webtools"))document.documentElement.dataset.tbSignedIn="1"}catch(e){}`;

export function TacticsboardEntry({ product, children }: { product: React.ReactNode; children: React.ReactNode }) {
  const t = useT();
  const { ready, available, session } = useAccount();
  if (ready && !(available && !session)) return <>{children}</>;
  return (
    <div className="tb-entry" data-pending={!ready}>
      {!ready && <script dangerouslySetInnerHTML={{ __html: remembersSignIn }} />}
      <p className="wt-wrap wt-section wt-status tb-entry-wait">{t("Laddar…")}</p>
      {product}
    </div>
  );
}
