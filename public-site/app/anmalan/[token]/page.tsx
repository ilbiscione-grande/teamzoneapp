import type { Metadata } from "next";
import { IntakeForm } from "../../../components/intake-form";
import { PortalFooter, PortalHeader, PortalHero, portalClass } from "../../../components/portal";
import { serverConfig } from "../../../lib/config";
import { validIntakeToken } from "../../../lib/intake";
import { publicRpc } from "../../../lib/public-rpc";
import { createServerSupabase } from "../../../lib/supabase-admin";

export const dynamic = "force-dynamic";
type Props = { params: Promise<{ token: string }> };
type IntakeFormInfo = { club_name: string; team_name?: string | null } | null;

export const metadata: Metadata = { title: "Kontaktuppgifter", robots: { index: false, follow: false } };

async function loadForm(token: string): Promise<IntakeFormInfo> {
  if (!validIntakeToken(token)) return null;
  try {
    const data = await publicRpc(createServerSupabase(serverConfig()), "public_get_intake_form", { public_token: token });
    return data?.not_found ? null : (data as IntakeFormInfo);
  } catch {
    return null;
  }
}

export default async function IntakePage({ params }: Props) {
  const { token } = await params;
  const form = await loadForm(token);
  if (!form) {
    return <main className={portalClass}><PortalHeader /><PortalHero kicker="Kontaktuppgifter" title="Sidan är inte längre öppen."><p className="pz-lead">Sidan gäller i 14 dagar och kan också ha stängts av klubben. Be din ledare om en ny länk eller QR-kod.</p></PortalHero><PortalFooter /></main>;
  }
  const receiver = form.team_name ? `${form.team_name} · ${form.club_name}` : form.club_name;
  return (
    <main className={portalClass}>
      <PortalHeader />
      <PortalHero kicker={receiver} title="Dina kontaktuppgifter">
        <p className="pz-lead">Fyll i dina uppgifter så att klubbens ledare kan lägga till dig i laget och nå dig.</p>
      </PortalHero>
      <section className="cs-section alt">
        <div className="cs-wrap pz-intake">
          <IntakeForm token={token} receiver={receiver} />
        </div>
      </section>
      <PortalFooter />
    </main>
  );
}
