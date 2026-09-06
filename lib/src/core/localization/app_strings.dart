import 'package:flutter/widgets.dart';

class AppStrings {
  const AppStrings._(this.isSwedish);

  final bool isSwedish;

  static AppStrings of(BuildContext context) => AppStrings._(
    Localizations.localeOf(context).languageCode.toLowerCase() == 'sv',
  );

  String get signInTimeout => isSwedish
      ? 'Inloggningen tog för lång tid. Försök igen.'
      : 'Sign-in timed out. Please try again.';
  String get signInFailed => isSwedish
      ? 'Inloggningen misslyckades. Kontrollera uppgifterna.'
      : 'Sign-in failed. Check your details.';
  String environment(String name) =>
      isSwedish ? 'Miljö: $name' : 'Environment: $name';
  String get backendNotConnected =>
      isSwedish ? 'Backend är inte ansluten' : 'Backend is not connected';
  String get backendInstructions => isSwedish
      ? 'Starta med SUPABASE_URL och SUPABASE_PUBLISHABLE_KEY. Secret- och service-role-nycklar får aldrig användas i klienten.'
      : 'Start with SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY. Secret and service-role keys must never be used in the client.';
  String get email => isSwedish ? 'E-post' : 'Email';
  String get password => isSwedish ? 'Lösenord' : 'Password';
  String get emailRequired =>
      isSwedish ? 'Ange din e-postadress.' : 'Enter your email address.';
  String get emailInvalid => isSwedish
      ? 'Ange en giltig e-postadress.'
      : 'Enter a valid email address.';
  String get passwordRequired =>
      isSwedish ? 'Ange ditt lösenord.' : 'Enter your password.';
  String get signIn => isSwedish ? 'Logga in' : 'Sign in';
  String get startupFailed =>
      isSwedish ? 'TeamZone kunde inte starta' : 'TeamZone could not start';
  String get retryProfile => isSwedish
      ? 'Din session är kvar. Försök att hämta profilen igen.'
      : 'Your session is still active. Try loading your profile again.';
  String get retry => isSwedish ? 'Försök igen' : 'Try again';
  String get loading => isSwedish ? 'Laddar' : 'Loading';
  String get cancel => isSwedish ? 'Avbryt' : 'Cancel';
  String get continueAction => isSwedish ? 'Fortsätt' : 'Continue';
  String get create => isSwedish ? 'Skapa' : 'Create';
  String get save => isSwedish ? 'Spara' : 'Save';
  String get close => isSwedish ? 'Stäng' : 'Close';
  String get reason => isSwedish ? 'Orsak' : 'Reason';
  String eligiblePlayersSaved(int count) => isSwedish
      ? '$count behöriga spelare sparades i truppen.'
      : '$count eligible players were saved to the squad.';
  String pricePerInterval(String price, bool monthly) => isSwedish
      ? '$price / ${monthly ? 'månad' : 'år'}'
      : '$price / ${monthly ? 'month' : 'year'}';
  String planCapacity(int teams, int? people) => isSwedish
      ? 'Upp till $teams lag och $people personer'
      : 'Up to $teams teams and $people people';
  String matchFinishedClock(String value) =>
      isSwedish ? 'Sluttid $value' : 'Full time $value';
  String matchPausedClock(String value) =>
      isSwedish ? 'Pausad $value' : 'Paused $value';
  String startPeriod(int period) =>
      isSwedish ? 'Starta period $period' : 'Start period $period';
  String endPeriod(int period) =>
      isSwedish ? 'Avsluta period $period' : 'End period $period';
  String periodEnded(int period) =>
      isSwedish ? 'Period $period avslutad' : 'Period $period ended';
  String get statusLabel => isSwedish ? 'Status' : 'Status';
  String get revisionLabel => isSwedish ? 'revision' : 'revision';
  String get deliveryLabel => isSwedish ? 'leverans' : 'delivery';
  String get periodLabel => isSwedish ? 'Period' : 'Period';
  String domainValue(String value) => switch (value) {
    'draft' => isSwedish ? 'Utkast' : 'Draft',
    'scheduled' => isSwedish ? 'Planerad' : 'Scheduled',
    'active' => isSwedish ? 'Aktiv' : 'Active',
    'locked' => isSwedish ? 'Låst' : 'Locked',
    'pending' => isSwedish ? 'Väntar' : 'Pending',
    'approved' => isSwedish ? 'Godkänd' : 'Approved',
    'rejected' => isSwedish ? 'Avslagen' : 'Rejected',
    'withdrawn' => isSwedish ? 'Återkallad' : 'Withdrawn',
    'issued' => isSwedish ? 'Utfärdad' : 'Issued',
    'revoked' => isSwedish ? 'Återkallad' : 'Revoked',
    'expired' => isSwedish ? 'Utgången' : 'Expired',
    'consumed' => isSwedish ? 'Använd' : 'Used',
    'accepted' => isSwedish ? 'Accepterad' : 'Accepted',
    'declined' => isSwedish ? 'Avböjd' : 'Declined',
    'cancelled' => isSwedish ? 'Inställd' : 'Cancelled',
    'completed' => isSwedish ? 'Genomförd' : 'Completed',
    'open' => isSwedish ? 'Öppen' : 'Open',
    'dismissed' => isSwedish ? 'Avfärdad' : 'Dismissed',
    'archived' => isSwedish ? 'Arkiverad' : 'Archived',
    'planning' => isSwedish ? 'Planering' : 'Planning',
    'live' => isSwedish ? 'Live' : 'Live',
    'published' => isSwedish ? 'Publicerad' : 'Published',
    'unpublished' => isSwedish ? 'Avpublicerad' : 'Unpublished',
    'present' => isSwedish ? 'Närvarande' : 'Present',
    'late' => isSwedish ? 'Sen' : 'Late',
    'partial' => isSwedish ? 'Delvis' : 'Partial',
    'absent' => isSwedish ? 'Frånvarande' : 'Absent',
    'unknown' => isSwedish ? 'Okänd' : 'Unknown',
    'sent' => isSwedish ? 'Skickad' : 'Sent',
    'delivered' => isSwedish ? 'Levererad' : 'Delivered',
    'failed' => isSwedish ? 'Misslyckad' : 'Failed',
    'team' => isSwedish ? 'Lag' : 'Team',
    'player' => isSwedish ? 'Spelare' : 'Player',
    'manual' => isSwedish ? 'Manuell' : 'Manual',
    'development' => isSwedish ? 'Utvecklingsspel' : 'Development play',
    'dispensation' => isSwedish ? 'Dispens' : 'Dispensation',
    'loan' => isSwedish ? 'Lån' : 'Loan',
    'guest' => isSwedish ? 'Gästspel' : 'Guest play',
    'season' => isSwedish ? 'Säsong' : 'Season',
    'fixed' => isSwedish ? 'Valt slutdatum' : 'Selected end date',
    'indefinite' => isSwedish ? 'Tills vidare' : 'Until further notice',
    'review_due' => isSwedish ? 'Granskning krävs' : 'Review required',
    'training' => isSwedish ? 'Träning' : 'Training',
    'match' => isSwedish ? 'Match' : 'Match',
    'meeting' => isSwedish ? 'Möte' : 'Meeting',
    'activity' => isSwedish ? 'Aktivitet' : 'Activity',
    'players' => isSwedish ? 'Spelare' : 'Players',
    'leaders' => isSwedish ? 'Ledare' : 'Leaders',
    'guardians' => isSwedish ? 'Vårdnadshavare' : 'Guardians',
    'leader' => isSwedish ? 'Ledare' : 'Leader',
    'guardian' => isSwedish ? 'Vårdnadshavare' : 'Guardian',
    'club_functionary' => isSwedish ? 'Klubbfunktionär' : 'Club official',
    'club' => isSwedish ? 'Hela klubben' : 'Entire club',
    _ => value.replaceAll('_', ' '),
  };
  String feature(String swedish) {
    if (isSwedish) return swedish;
    return _featureEnglish[swedish] ??
        (throw StateError('Missing English feature copy: $swedish'));
  }

  static const Map<String, String> _featureEnglish = {
    'Ansök': 'Apply',
    'Ansök som': 'Apply as',
    'Ange ett klubbnamn med 2–120 tecken.':
        'Enter a club name containing 2–120 characters.',
    'Ange ett lagnamn med 1–120 tecken.':
        'Enter a team name containing 1–120 characters.',
    'Ansökan kunde inte skickas.': 'The application could not be sent.',
    'Ansökan kunde inte återkallas.': 'The application could not be withdrawn.',
    'Ansökningarna kunde inte hämtas.': 'The applications could not be loaded.',
    'Ansökningarna kunde inte hämtas': 'The applications could not be loaded',
    'Avslå': 'Reject',
    'Avslå medlemsansökan?': 'Reject membership application?',
    'Beslutet kunde inte sparas. Ladda om och försök igen.':
        'The decision could not be saved. Reload and try again.',
    'Godkänn medlemsansökan?': 'Approve membership application?',
    'Hitta klubb eller lag': 'Find a club or team',
    'Hämtar medlemsansökningar': 'Loading membership applications',
    'Inga väntande medlemsansökningar': 'No pending membership applications',
    'Inofficiell klubb': 'Unofficial club',
    'Klubbverifiering': 'Club verification',
    'Se officiell status eller skicka underlag till TeamZone.':
        'View official status or submit evidence to TeamZone.',
    'Laddar klubbstatus': 'Loading club status',
    'Klubbstatus kunde inte laddas': 'Club status could not be loaded',
    'Försök igen om en stund.': 'Please try again shortly.',
    'Klubben är granskad och godkänd av TeamZone.':
        'The club has been reviewed and approved by TeamZone.',
    'Granskning pågår': 'Review in progress',
    'TeamZone har tagit emot klubbens underlag.':
        'TeamZone has received the club evidence.',
    'Verifiering avslagen': 'Verification rejected',
    'Klubben är fortsatt inofficiell.': 'The club remains unofficial.',
    'Officiell status återkallad': 'Official status revoked',
    'Kontakta TeamZone om klubben ska granskas igen.':
        'Contact TeamZone if the club should be reviewed again.',
    'Klubben är ännu inte verifierad av TeamZone.':
        'The club has not yet been verified by TeamZone.',
    'Beskriv kopplingen till klubben med 20–1000 tecken.':
        'Describe your connection to the club using 20–1000 characters.',
    'Underlaget kunde inte skickas. Försök igen.':
        'The evidence could not be submitted. Please try again.',
    'Underlag för granskning': 'Evidence for review',
    'Beskriv din roll och hur TeamZone kan verifiera kopplingen till klubben.':
        'Describe your role and how TeamZone can verify your connection to the club.',
    'Skicka för granskning': 'Submit for review',
    'Namnet är skyddat eller används redan. Välj ett tydligt alternativt namn eller kontakta TeamZone för granskning.':
        'The name is protected or already in use. Choose a clearly different name or contact TeamZone for review.',
    'Klubbnamnet kan inte användas. Kontrollera namnet och försök igen.':
        'The club name cannot be used. Check the name and try again.',
    'Villkor kunde inte kontrolleras': 'Terms could not be checked',
    'Ingen klubb- eller lagdata visas förrän kontrollen lyckas.':
        'No club or team data is shown until the check succeeds.',
    'Dokumentet kunde inte öppnas. Försök igen.':
        'The document could not be opened. Please try again.',
    'Godkännandet kunde inte sparas. Läs in den aktuella versionen och försök igen.':
        'The acceptance could not be saved. Load the current version and try again.',
    'Villkor och integritet': 'Terms and privacy',
    'Läs och godkänn för att fortsätta': 'Read and accept to continue',
    'Obligatoriska dokument är separerade från frivillig marknadsföring.':
        'Mandatory documents are separate from optional marketing.',
    'Jag godkänner användarvillkoren': 'I accept the terms of service',
    'Jag har läst integritetspolicyn': 'I have read the privacy policy',
    'Version {version}': 'Version {version}',
    'Öppna användarvillkor': 'Open terms of service',
    'Öppna integritetspolicy': 'Open privacy policy',
    'Jag vill få marknadsföring från TeamZone':
        'I want to receive marketing from TeamZone',
    'Frivilligt och kan återkallas när som helst.':
        'Optional and can be withdrawn at any time.',
    'Sparar…': 'Saving…',
    'Godkänn och fortsätt': 'Accept and continue',
    'Integritetsinställningar': 'Privacy settings',
    'Inställningen kunde inte sparas. Försök igen.':
        'The setting could not be saved. Please try again.',
    'Inställningen kunde inte laddas': 'The setting could not be loaded',
    'Marknadsföring från TeamZone': 'Marketing from TeamZone',
    'Frivilligt. Avstängt påverkar inte appens funktioner.':
        'Optional. Turning it off does not affect app functionality.',
    'Lagets innehåll': 'Team content',
    'Översikt': 'Overview',
    'Kalender': 'Calendar',
    'Ingen lagbild': 'No team image',
    'Redigera lagprofil': 'Edit team profile',
    'Lagtyp': 'Team type',
    'Kort lagpresentation': 'Short team presentation',
    'Lagbildens HTTPS-adress': 'Team image HTTPS address',
    'Säker bilduppladdning läggs till separat.':
        'Secure image upload will be added separately.',
    'Ange en giltig HTTPS-adress.': 'Enter a valid HTTPS address.',
    'Lagprofilen kunde inte laddas.': 'The team profile could not be loaded.',
    'Lagprofilen kunde inte sparas.': 'The team profile could not be saved.',
    'Lagets grundinformation och rollanpassade genvägar byggs vidare i TEAM-02.':
        'Team information and role-adapted shortcuts continue in TEAM-02.',
    'Laddar lagets kalender': 'Loading team calendar',
    'Lagets kalender kunde inte laddas':
        'The team calendar could not be loaded',
    'Alla': 'All',
    'Kanske': 'Maybe',
    'Kan inte': 'Cannot attend',
    'Fortsätt': 'Continue',
    'Olästa meddelanden': 'Unread messages',
    'Öppna inkorgen för att läsa': 'Open the inbox to read',
    'Bekräfta': 'Confirm',
    'Läs alla': 'Read all',
    'Dölj konversation': 'Hide conversation',
    'Lämna konversation': 'Leave conversation',
    'Stäng för nya meddelanden': 'Close for new messages',
    'Historiken bevaras men ingen kan skicka nya meddelanden.':
        'History is preserved but no one can send new messages.',
    'Fler alternativ': 'More options',
    'Dölj för mig': 'Hide for me',
    'Dela med andra lag': 'Share with other teams',
    'Ta bort utkast': 'Delete draft',
    'Arkivera event': 'Archive event',
    'Urval': 'Selection',
    'Deltagaruppgifter är inte tillgängliga':
        'Participant information is unavailable',
    'Förbered deltagare och kallelser': 'Prepare participants and call-ups',
    'Uppdatera eventinformation': 'Update event information',
    'Uppföljning': 'Follow-up',
    'Registrera och granska närvaro': 'Record and review attendance',
    'Följ upp matchen': 'Review the match',
    'Delningsinställningarna kunde inte laddas.':
        'Sharing settings could not be loaded.',
    'Dela event': 'Share event',
    'Det finns inga andra aktiva lag i klubben.':
        'There are no other active teams in the club.',
    'Ingen delning': 'No sharing',
    'Kan se': 'Can view',
    'Kan hantera deltagare': 'Can manage participants',
    'Kan samredigera eventet': 'Can co-edit the event',
    'Mottagare (ger endast synlighet)': 'Recipient (visibility only)',
    'Delningen har sparats.': 'Sharing has been saved.',
    'Ta bort utkast?': 'Delete draft?',
    'Ta bort': 'Delete',
    'Utkastet har tagits bort.': 'The draft has been deleted.',
    'Arkivera': 'Archive',
    'Eventet har arkiverats.': 'The event has been archived.',
    'Eventet kunde inte arkiveras.': 'The event could not be archived.',
    'Behöriga deltagare kunde inte laddas.':
        'Eligible participants could not be loaded.',
    'Manuell': 'Manual',
    'Generator': 'Generator',
    'Spara draft': 'Save draft',
    'Nyhetsredaktion': 'Newsroom',
    'Redaktionen är inte tillgänglig': 'The newsroom is unavailable',
    'Ditt aktuella klubbmandat saknar publiceringsbehörighet.':
        'Your current club mandate does not include publishing access.',
    'Uppdatera': 'Refresh',
    'Ny artikel': 'New article',
    'Redigera artikel': 'Edit article',
    'Laddar artiklar': 'Loading articles',
    'Artiklarna kunde inte laddas': 'Articles could not be loaded',
    'Inga artiklar ännu': 'No articles yet',
    'Skapa ett utkast och välj sedan när det ska publiceras.':
        'Create a draft and then choose when to publish it.',
    'Klubbkanal': 'Club channel',
    'Endast lagkanaler': 'Team channels only',
    'Artikelåtgärder': 'Article actions',
    'Schemalägg': 'Schedule',
    'Publicera nu': 'Publish now',
    'Avpublicera': 'Unpublish',
    'Adressnamn': 'URL slug',
    'Ingress': 'Summary',
    'Artikeltext': 'Article text',
    'Avsändare': 'Byline',
    'Visa i klubbkanalen': 'Show in the club channel',
    'Visa i lagkanalen': 'Show in the team channel',
    'Välj minst en klubb- eller lagkanal.':
        'Select at least one club or team channel.',
    'Spara utkast': 'Save draft',
    'Bilder är inte aktiverade ännu. Endast strukturerad text publiceras.':
        'Images are not enabled yet. Only structured text is published.',
    'Event och partners': 'Events and partners',
    'Förhandsgranska händelse': 'Preview event',
    'Publik titel': 'Public title',
    'Visa plats publikt': 'Show location publicly',
    'Gör privat': 'Make private',
    'Publicera': 'Publish',
    'Ny partner': 'New partner',
    'Redigera partner': 'Edit partner',
    'Namn': 'Name',
    'HTTPS-adress': 'HTTPS address',
    'Sortering': 'Sort order',
    'Partnerlogotyp kommer senare': 'Partner logo is coming later',
    'Säker mediaworker är ännu inte konfigurerad.':
        'The secure media worker is not configured yet.',
    'Publiceringsdata kunde inte laddas':
        'Publication data could not be loaded',
    'Publika händelser': 'Public events',
    'Endast titel, tid, typ och uttryckligt vald plats publiceras.':
        'Only title, time, type and an explicitly selected location are published.',
    'Inga publicerbara händelser': 'No publishable events',
    'Hantera publicering': 'Manage publication',
    'Partners': 'Partners',
    'Partnerhantering kräver klubbmandat.':
        'Partner management requires a club mandate.',
    'Domäner': 'Domains',
    'Anslut egen domän': 'Connect a custom domain',
    'Domännamn': 'Domain name',
    'Domänen aktiveras först efter betalningsgodkännande, DNS-verifiering och färdigt TLS-certifikat.':
        'The domain is activated only after payment approval, DNS verification and a ready TLS certificate.',
    'Skapa DNS-instruktion': 'Create DNS instructions',
    'DNS-instruktion': 'DNS instructions',
    'Token visas bara vid första begäran':
        'The token is only shown with the first request',
    'Klar': 'Done',
    'Egen domän': 'Custom domain',
    'Domänstatus kunde inte laddas': 'Domain status could not be loaded',
    'Kostnadsfri standardadress': 'Free standard address',
    'Publicera klubbsidan först': 'Publish the club page first',
    'Premiumsubdomän kommer senare': 'Premium subdomain is coming later',
    'Wildcard DNS, TLS och automatisk routing är ännu inte aktiverade.':
        'Wildcard DNS, TLS and automatic routing are not enabled yet.',
    'Använd standardadressen som huvudadress':
        'Use the standard address as the primary address',
    'Använd som huvudadress': 'Use as primary address',
    'Fältet krävs': 'This field is required',
    'Använd små bokstäver, siffror och bindestreck.':
        'Use lowercase letters, numbers and hyphens.',
    'Varför kan du inte delta?': 'Why can you not participate?',
    'Sjukdom': 'Illness',
    'Inte tillgänglig': 'Unavailable',
    'Transport': 'Transport',
    'Annat': 'Other',
    'Beskriv anledning': 'Describe the reason',
    'Skicka svar': 'Send response',
    'Registrera närvaro': 'Record attendance',
    'Närvarobehörigheten kunde inte kontrolleras.':
        'Attendance permission could not be checked.',
    'Sen närvarokorrigering kräver särskild behörighet.':
        'Late attendance correction requires additional permission.',
    'Du saknar behörighet att registrera närvaro.':
        'You do not have permission to record attendance.',
    'Okänd är neutralt och räknas aldrig som närvarande eller frånvarande.':
        'Unknown is neutral and is never counted as present or absent.',
    'Orsak till sen korrigering': 'Reason for late correction',
    'Minuter sen': 'Minutes late',
    'Deltagna minuter': 'Minutes participated',
    'Spara ändringar': 'Save changes',
    'Närvaron har sparats.': 'Attendance has been saved.',
    'Närvaron kunde inte sparas. Ladda om och försök igen.':
        'Attendance could not be saved. Reload and try again.',
    'Aktiva': 'Active',
    'Övriga': 'Other',
    'Truppen är inte tillgänglig': 'The roster is not available',
    'Du är inte kopplad till något lag': 'You are not connected to a team',
    'När du blir tillagd i ett lag visas lagets översikt, trupp och kalender här.':
        'When you are added to a team, its overview, roster and calendar will appear here.',
    'Din roll saknar behörighet att visa den här truppen.':
        'Your role does not have permission to view this roster.',
    'Välj en person': 'Select a person',
    'Medlemsdetaljer visas här utan att lämna truppen.':
        'Member details are shown here without leaving the roster.',
    'Laddar medlemsdetaljer': 'Loading member details',
    'Medlemsdetaljen kunde inte laddas':
        'The member details could not be loaded',
    'Kontrollera din behörighet och försök igen.':
        'Check your permission and try again.',
    'Lag': 'Team',
    'Åldersklass': 'Age group',
    'Status': 'Status',
    'Administrativa uppgifter': 'Administrative details',
    'Ursprung': 'Source',
    'Startdatum': 'Start date',
    'Slutdatum': 'End date',
    'Lägg till person': 'Add person',
    'Skapa en klubbägd rosterprofil i det här laget.':
        'Create a club-owned roster profile in this team.',
    'Redigera person': 'Edit person',
    'Personen kunde inte redigeras': 'The person could not be edited',
    'Ladda om truppen och kontrollera din behörighet.':
        'Reload the roster and check your permission.',
    'Personen kunde inte sparas. Kontrollera dubbletter och ladda om innan du försöker igen.':
        'The person could not be saved. Check for duplicates and reload before trying again.',
    'Dina ändringar har inte sparats.': 'Your changes have not been saved.',
    'Uppgifterna tillhör klubben och ändrar inte användarens globala identitet.':
        "These details belong to the club and do not change the user's global identity.",
    'Visningsnamn': 'Display name',
    'Ange ett namn med 1–120 tecken.':
        'Enter a name containing 1–120 characters.',
    'Åldersklass (valfri)': 'Age group (optional)',
    'Ange högst 40 tecken.': 'Enter no more than 40 characters.',
    'Spara person': 'Save person',
    'Använd inbjudan eller lagkod': 'Use invitation or team code',
    'Lagkod': 'Team code',
    'Använd kod': 'Use code',
    'Medlemsansökan har skapats.':
        'The membership application has been created.',
    'Inbjudan eller lagkoden är ogiltig eller har gått ut.':
        'The invitation or team code is invalid or has expired.',
    'Inbjudningar och lagkoder': 'Invitations and team codes',
    'Skapa lagkod': 'Create team code',
    'Ansökningsroll': 'Application role',
    'Riktad inbjudan': 'Targeted invitation',
    'Mottagarens e-post': "Recipient's email",
    'Ange en giltig e-postadress.': 'Enter a valid email address.',
    'Guardian': 'Guardian',
    'Barn': 'Child',
    'Behöver vårdnadshavarkoppling': 'Needs a guardian connection',
    'Gör personen valbar som barn i en guardianinbjudan.':
        'Makes the person selectable as the child in a guardian invitation.',
    'Markera först ett barn som behöver vårdnadshavarkoppling.':
        'First mark a child as needing a guardian connection.',
    'Koden är skapad': 'The code has been created',
    'Visa kod': 'Show code',
    'Kopiera': 'Copy',
    'Lagkoden har kopierats.': 'The team code has been copied.',
    'Inbjudningskoden har kopierats.': 'The invitation code has been copied.',
    'Lagkoden kan inte visas. Återkalla den och skapa en ny kod.':
        'The team code cannot be shown. Revoke it and create a new code.',
    'Inbjudan kunde inte skapas.': 'The invitation could not be created.',
    'Inbjudan kunde inte återkallas.': 'The invitation could not be revoked.',
    'Koder visas bara en gång. Status och återkallelse finns kvar här.':
        'Codes are shown once. Status and revocation remain available here.',
    'Lagkoder kan visas och kopieras igen. Personliga koder visas bara en gång.':
        'Team codes can be shown and copied again. Personal codes are shown only once.',
    'Riktad': 'Targeted',
    'Laddar inbjudningar': 'Loading invitations',
    'Inbjudningarna kunde inte laddas': 'The invitations could not be loaded',
    'Inga inbjudningar': 'No invitations',
    'Skapa en riktad inbjudan, guardianinbjudan eller lagkod.':
        'Create a targeted invitation, guardian invitation or team code.',
    'Guardianrelationen kunde inte avslutas.':
        'The guardian relationship could not be ended.',
    'Avsluta': 'End',
    'Representation i andra lag': 'Representation in other teams',
    'Ny representation': 'New representation',
    'Person': 'Person',
    'Giltighet': 'Validity',
    'Granskas senast': 'Review by',
    'Gäller till': 'Valid until',
    'Beslutsunderlag': 'Decision basis',
    'Representationen kunde inte sparas. Kontrollera lag, period och överlapp.':
        'The representation could not be saved. Check the team, period and overlap.',
    'Ordinarie lag och historik ändras inte.':
        'The home team and history are not changed.',
    'Ny': 'New',
    'Laddar representationer': 'Loading representations',
    'Representationerna kunde inte laddas':
        'The representations could not be loaded',
    'Inga representationer': 'No representations',
    'Spelare kan få tidsbegränsad rätt att representera ett annat lag.':
        'Players can receive time-limited permission to represent another team.',
    'Matcher': 'Matches',
    'Träningar': 'Training sessions',
    'Möten': 'Meetings',
    'Kommande': 'Upcoming',
    'Tidigare': 'Previous',
    'Inga händelser': 'No events',
    'Laddar lagöversikt': 'Loading team overview',
    'Lagöversikten kunde inte laddas': 'The team overview could not be loaded',
    'Försök igen. Ingen administrativ information visas.':
        'Please try again. No administrative information is shown.',
    'Ingen laginformation har publicerats ännu.':
        'No team information has been published yet.',
    'Inga ledare visas ännu.': 'No coaches are shown yet.',
    'Öppna trupp': 'Open roster',
    'Öppna lagkalender': 'Open team calendar',
    'Öppna Inbox': 'Open Inbox',
    'Kräver åtgärd': 'Requires action',
    'Aktiva inbjudningar': 'Active invitations',
    'Väntande ansökningar': 'Pending applications',
    'Totalt {count} ärenden kräver åtgärd.':
        'A total of {count} items require action.',
    '{count} ärenden totalt': '{count} items in total',
    'Lagbild för {team}': 'Team image for {team}',
    'Klubb eller lag': 'Club or team',
    'Klubben kunde inte skapas. Kontrollera namnen och försök igen.':
        'The club could not be created. Check the names and try again.',
    'Klubben skapas som inofficiell. Du blir klubbadministratör och får en aktiv lagkontext.':
        'The club is created as unofficial. You become club administrator and receive an active team context.',
    'Klubbnamn': 'Club name',
    'Lagnamn': 'Team name',
    'Laget har skapats.': 'The team has been created.',
    'Laget kunde inte skapas. Försök igen.':
        'The team could not be created. Please try again.',
    'Klubbfunktionär': 'Club official',
    'Ledare': 'Coach',
    'Mina ansökningar': 'My applications',
    'Medlemsansökningar': 'Membership applications',
    'Officiell klubb': 'Official club',
    'Skicka ansökan': 'Send application',
    'Skapa klubb och första lag': 'Create club and first team',
    'Skapa klubb och lag': 'Create club and team',
    'Skapa lag': 'Create team',
    'Skapa ytterligare lag': 'Create another team',
    'Första lagets namn': 'First team name',
    'Personen får den valda rollen i laget.':
        'The person receives the selected role in the team.',
    'Sökanden ser endast att ansökan har avslagits.':
        'The applicant only sees that the application was rejected.',
    'Sök med minst tre tecken. Endast grundläggande, offentlig organisationsinformation visas.':
        'Search using at least three characters. Only basic public organization information is shown.',
    'Sökningen kunde inte genomföras. Försök igen.':
        'The search could not be completed. Please try again.',
    'Vårdnadshavare': 'Guardian',
    'Dra tillbaka ansökan': 'Withdraw application',
    'Acceptera som guardian': 'Accept as guardian',
    'Acceptera': 'Accept',
    'Avbryt': 'Cancel',
    'Avvisa': 'Reject',
    'Blockera': 'Block',
    'Frys accepterad matchtrupp': 'Freeze accepted match squad',
    'Minst en accepterad kallelse krävs innan matchtruppen kan frysas.':
        'At least one accepted call-up is required before the match squad can be frozen.',
    'Förfrågningar': 'Requests',
    'Fler inkorgsåtgärder': 'More inbox actions',
    'Slå på notiser': 'Turn on notifications',
    'Försök igen med samma kommando': 'Retry the same command',
    'Försök igen': 'Try again',
    'Guardianinbjudan': 'Guardian invitation',
    'Hantera': 'Manage',
    'Inga kallelser skickade.': 'No call-ups sent.',
    'Inga matchhändelser registrerade.': 'No match events recorded.',
    'Kontaktförfrågningar': 'Contact requests',
    'Ledarkontakt': 'Coach contact',
    'Lås trupp': 'Lock squad',
    'Lås upp match': 'Unlock match',
    'Lås upp med orsak': 'Unlock with reason',
    'Lås upp': 'Unlock',
    'Lägg till åtgärd': 'Add action',
    'Lägg till': 'Add',
    'Markera genomfört': 'Mark completed',
    'Match': 'Match',
    'Matchen är inte förberedd ännu.': 'The match is not prepared yet.',
    'Mål motståndare': 'Opponent goal',
    'Mål vi': 'Our goal',
    'Minimal rosterprofil': 'Minimal roster profile',
    'Notiser': 'Notifications',
    'Ny lagplan': 'New team plan',
    'Ny åtgärd': 'New action',
    'Nytt event': 'New event',
    'Rapportera och blockera': 'Report and block',
    'Redigera event': 'Edit event',
    'Redigera': 'Edit',
    'Skapa event': 'Create event',
    'Skapa konto': 'Create account',
    'E-postkod/länk': 'Email code/link',
    'E-postkod': 'Email code',
    'Bekräfta lösenord': 'Confirm password',
    'Glömt lösenord?': 'Forgot password?',
    'Skicka e-postkod/länk': 'Send email code/link',
    'Verifiera kod': 'Verify code',
    'Skicka ny kod': 'Send a new code',
    'Skicka ny kod om {seconds} s': 'Send a new code in {seconds} s',
    'Nytt lösenord': 'New password',
    'Spara lösenord': 'Save password',
    'Lösenordet måste innehålla minst 8 tecken.':
        'The password must contain at least 8 characters.',
    'Lösenorden måste vara identiska.': 'The passwords must match.',
    'Kontrollera din e-post och verifiera adressen innan du loggar in.':
        'Check your email and verify the address before signing in.',
    'Vi har skickat en e-postkod eller säker inloggningslänk.':
        'We sent an email code or secure sign-in link.',
    'Koden gäller i 10 minuter. Du kan också använda länken i mejlet.':
        'The code is valid for 10 minutes. You can also use the link in the email.',
    'Koden har gått ut.': 'The code has expired.',
    'Koden har gått ut. Skicka en ny kod.':
        'The code has expired. Send a new code.',
    'Om adressen är registrerad skickas instruktioner för att återställa lösenordet.':
        'If the address is registered, password reset instructions will be sent.',
    'Det gick inte att slutföra åtgärden. Kontrollera uppgifterna och försök igen.':
        'The action could not be completed. Check the details and try again.',
    'Lösenordet uppfyller inte säkerhetskraven. Välj ett längre och mindre vanligt lösenord.':
        'The password does not meet the security requirements. Choose a longer and less common password.',
    'För många försök har gjorts. Vänta en stund innan du försöker igen.':
        'Too many attempts have been made. Wait a while before trying again.',
    'E-postadressen kan inte användas. Kontrollera adressen eller använd en annan.':
        'The email address cannot be used. Check the address or use another one.',
    'Det gick inte att skapa kontot. Prova att logga in eller återställa lösenordet.':
        'The account could not be created. Try signing in or resetting the password.',
    'Det går inte att skapa konto med e-post just nu.':
        'Accounts cannot be created with email right now.',
    'Lösenordet kunde inte uppdateras. Begär en ny återställningslänk.':
        'The password could not be updated. Request a new recovery link.',
    'Skapa': 'Create',
    'Ny konversation': 'New conversation',
    'Direkt': 'Direct',
    'Grupp': 'Group',
    'Gruppnamn': 'Group name',
    'Info': 'Info',
    'Deltagare': 'Participants',
    'Förberedelser': 'Preparation',
    'Kallelser och svar': 'Call-ups and responses',
    'Din roll kan sakna åtkomst eller informationen kunde inte laddas.':
        'Your role may lack access, or the information could not be loaded.',
    'Rubrik': 'Subject',
    'Markera alla som lästa': 'Mark all as read',
    'Visa äldre meddelanden': 'Show older messages',
    'Försök skicka igen': 'Try sending again',
    'Skickar…': 'Sending…',
    'Fästa': 'Pinned',
    'Inställningar': 'Settings',
    'Meddelandeinställningar': 'Message settings',
    'Frivilliga pushnotiser': 'Optional push notifications',
    'Av som standard. Låsskärmen visar bara att ett nytt meddelande finns.':
        'Off by default. The lock screen only shows that a new message exists.',
    'Inställningen sparades': 'Setting saved',
    'Fäst tråd': 'Pin thread',
    'Lossa tråd': 'Unpin thread',
    'Varför rapporterar du?': 'Why are you reporting this?',
    'Rapporten blockerar också avsändaren.':
        'The report also blocks the sender.',
    'Trakasserier': 'Harassment',
    'Sexuellt innehåll': 'Sexual content',
    'Hot': 'Threat',
    'Spam': 'Spam',
    'Endast information': 'Announcement only',
    'Bara avsändaren kan skriva i den här konversationen.':
        'Only the sender can post in this conversation.',
    'Lägg till deltagare': 'Add participants',
    'Deltagare tillagda': 'Participants added',
    'Skicka kallelser': 'Send call-ups',
    'Spara': 'Save',
    'Starta match': 'Start match',
    'Ställ in': 'Cancel event',
    'Stäng': 'Close',
    'Sök': 'Search',
    'Tillåtna verifierade ledare': 'Allowed verified coaches',
    'Trupp, kallelser och närvaro': 'Squad, call-ups and attendance',
    'Trupp': 'Squad',
    'Veckovis, fyra tillfällen': 'Weekly, four occurrences',
    'Verifierad ledarkontakt': 'Verified coach contact',
    'Återkalla meddelande': 'Recall message',
    'Beskrivning': 'Description',
    'Fokus': 'Focus',
    'Ledarnamn': 'Coach name',
    'Plats': 'Location',
    'Säker inbjudningskod': 'Secure invitation code',
    'Titel': 'Title',
    'Typ': 'Type',
    'Åtgärd': 'Action',
    'Ändra': 'Change',
    'Abonnemang hanteras av klubbadministratören på webben.':
        'Subscriptions are managed by the club administrator on the web.',
    'Du saknar behörighet att hantera klubbens abonnemang.':
        'You do not have permission to manage the club subscription.',
    'Försök igen.': 'Please try again.',
    'Försök igen. Inga råa backendfel visas.':
        'Please try again. No raw backend errors are shown.',
    'Rosterposter visas här när de har skapats.':
        'Roster entries appear here after they are created.',
    'Aktivitet': 'Activity',
    'Avböj': 'Decline',
    'Bara detta': 'This occurrence only',
    'Betalningen avbröts': 'The payment was cancelled',
    'Betalningen kunde inte startas. Försök igen.':
        'The payment could not be started. Please try again.',
    'Betalningen är mottagen': 'The payment was received',
    'Detta och framåt': 'This and following occurrences',
    'Eventdetaljer kunde inte laddas.': 'Event details could not be loaded.',
    'Eventet kunde inte skapas. Försök igen.':
        'The event could not be created. Please try again.',
    'Frånvarande': 'Absent',
    'Guardianinbjudan är ogiltig eller har gått ut.':
        'The guardian invitation is invalid or has expired.',
    'Guardianrelationen är aktiverad.': 'The guardian relationship is active.',
    'Sessionen har avslutats': 'Your session has ended',
    'Logga in igen för att fortsätta. Ingen skyddad data visas.':
        'Sign in again to continue. No protected data is shown.',
    'Delad enhet': 'Shared device',
    'Spara inte inloggningen i den här webbläsaren.':
        'Do not save the sign-in in this browser.',
    'Inbjudan': 'Invitation',
    'Inbjudan är inte tillgänglig': 'Invitation is unavailable',
    'Länken är ogiltig, återkallad eller har gått ut.':
        'The link is invalid, revoked, or has expired.',
    'Manuell granskning krävs': 'Manual review is required',
    'Vi kunde inte koppla inbjudan automatiskt. TeamZone visar inga kontouppgifter medan ärendet granskas.':
        'We could not link the invitation automatically. TeamZone shows no account details while the case is reviewed.',
    'Klart': 'Done',
    'Du har blivit inbjuden': 'You have been invited',
    'Giltig till': 'Valid until',
    'Acceptera inbjudan': 'Accept invitation',
    'Logga in för att fortsätta': 'Sign in to continue',
    'Inbjudan kunde inte accepteras. Kontrollera att den fortfarande gäller.':
        'The invitation could not be accepted. Check that it is still valid.',
    'Hela serien': 'The entire series',
    'Inga notiser': 'No notifications',
    'Inga tillåtna träffar': 'No allowed matches',
    'Inga väntande förfrågningar': 'No pending requests',
    'Ingen trupp är uttagen.': 'No squad has been selected.',
    'Kalendern kunde inte uppdateras. Försök igen.':
        'The calendar could not be updated. Please try again.',
    'Kontaktförfrågan skickad.': 'Contact request sent.',
    'Månad': 'Month',
    'Agenda': 'Agenda',
    'Vecka': 'Week',
    'Dag': 'Day',
    'Alla lag': 'All teams',
    'Eventtyp': 'Event type',
    'Alla eventtyper': 'All event types',
    'Föregående period': 'Previous period',
    'Idag': 'Today',
    'Nästa period': 'Next period',
    'Inga event i vald vy': 'No events in the selected view',
    'Byt datum eller justera filtren.':
        'Change the date or adjust the filters.',
    'Heldag': 'All day',
    'Start': 'Start',
    'Slut': 'End',
    'Tidszon': 'Time zone',
    'Audience': 'Audience',
    'Återkommande serie': 'Recurring series',
    'Intervalltyp': 'Interval type',
    'Dagligen': 'Daily',
    'Veckovis': 'Weekly',
    'Varje': 'Every',
    'Antal': 'Count',
    'Kontrollera titel, tid, audience och serieinställningar.':
        'Check the title, time, audience and series settings.',
    'Publicera event': 'Publish event',
    'Återställ event': 'Restore event',
    'Möte': 'Meeting',
    'Närvarande': 'Present',
    'Okänd': 'Unknown',
    'Planen har skapats.': 'The plan was created.',
    'Planen kunde inte skapas. Försök igen.':
        'The plan could not be created. Please try again.',
    'Påminn': 'Remind',
    'Rosteråtgärder': 'Roster actions',
    'Truppen kunde inte laddas.': 'The squad could not be loaded.',
    'Träning': 'Training',
    'År': 'Year',
    'Återkalla': 'Recall',
    'Åtgärden har lagts till.': 'The action was added.',
    'Åtgärden kunde inte sparas. Försök igen.':
        'The action could not be saved. Please try again.',
    'Ändringen är sparad.': 'The change was saved.',
    'Abonnemang': 'Subscription',
    'Abonnemang kunde inte laddas': 'The subscription could not be loaded',
    'Inga event i perioden': 'No events in this period',
    'Inga utvecklingsplaner ännu': 'No development plans yet',
    'Ingen i truppen ännu': 'No one in the roster yet',
    'Kalendern kunde inte synkroniseras': 'The calendar could not be synced',
    'Återansluter kalendern': 'Reconnecting the calendar',
    'Kalendern visar sparad data': 'The calendar is showing saved data',
    'Sök i truppen': 'Search the roster',
    'Sök i inkorgen': 'Search the inbox',
    'Inga matchande personer': 'No matching people',
    'Inga matchande konversationer': 'No matching conversations',
    'Ändra sökningen eller rensa filtret.':
        'Change the search or clear the filter.',
    'Rensa sökning': 'Clear search',
    'Olästa': 'Unread',
    'Tystade': 'Muted',
    'Visa fler': 'Show more',
    'Kasta ändringar?': 'Discard changes?',
    'Dina osparade ändringar går förlorade.':
        'Your unsaved changes will be lost.',
    'Kasta': 'Discard',
    'Fortsätt redigera': 'Keep editing',
    'Truppen kunde inte laddas': 'The roster could not be loaded',
    'Utvecklingsplaner är inte tillgängliga':
        'Development plans are not available',
    'Bifoga fil': 'Attach file',
    'Ekonomi': 'Economy',
    'Hantera kallelse': 'Manage call-up',
    'Styrelse': 'Board',
    'Svara på kallelse': 'Respond to call-up',
    'Synkronisera': 'Sync',
    'Inbjudan är ogiltig eller har gått ut.':
        'The invitation is invalid or has expired.',
    'Skyddad minderårigdata visas inte i rosterprojektionen.':
        'Protected minor data is not shown in the roster projection.',
    'Skapa, invite, guardian och transfer körs som scopeade serverkommandon.':
        'Create, invite, guardian and transfer use scoped server commands.',
    'Flytta spelare': 'Move player',
    'Flytta inom klubben med bevarad historik.':
        'Move within the club while preserving history.',
    'Spelare': 'Player',
    'Nytt lag': 'New team',
    'Flyttdatum': 'Move date',
    'Anledning': 'Reason',
    'Det tidigare laget och all historik bevaras.':
        'The previous team and all history are preserved.',
    'Flytta': 'Move',
    'Spelaren är flyttad.': 'The player has been moved.',
    'Flytten kunde inte sparas. Ladda om och kontrollera datum och lag.':
        'The move could not be saved. Reload and check the date and teams.',
    'Laddar flyttunderlag': 'Loading move options',
    'Flyttunderlaget kunde inte laddas': 'Move options could not be loaded',
    'Flytten avslutar nuvarande lagtillhörighet och skapar en ny från valt datum.':
        'The move ends the current team assignment and creates a new one from the selected date.',
    'Ingen flytt är möjlig': 'No move is possible',
    'Det behövs en aktiv spelare och minst ett annat aktivt lag i klubben.':
        'An active player and at least one other active team in the club are required.',
    'Arkivering och personuppgifter': 'Archiving and personal data',
    'Avsluta lagtillhörighet eller starta en skyddad raderingsbegäran.':
        'End a team assignment or start a protected erasure request.',
    'Arkivera från laget': 'Archive from team',
    'Personen flyttas till Tidigare. Historiska fakta bevaras.':
        'The person is moved to Previous. Historical facts are preserved.',
    'Begär radering av klubbuppgifter': 'Request erasure of club data',
    'En annan klubbansvarig måste godkänna. Namn och lokala personuppgifter anonymiseras, men verksamhetshistorik bevaras.':
        'Another club administrator must approve. The name and local personal data are anonymized, while operational history is preserved.',
    'Raderingsbegäran kunde inte skapas.':
        'The erasure request could not be created.',
    'Godkänn anonymisering': 'Approve anonymization',
    'Du måste vara en annan klubbansvarig än den som startade begäran. Åtgärden kan inte ångras i appen.':
        'You must be a different club administrator from the requester. The action cannot be undone in the app.',
    'Godkännandet nekades. Kontrollera behörighet och att initiatorn är en annan användare.':
        'Approval was denied. Check permission and that the requester is another user.',
    'Laddar livscykel': 'Loading lifecycle',
    'Livscykeln kunde inte laddas': 'The lifecycle could not be loaded',
    'Arkivering döljer inte historik. Personuppgiftsradering kräver två separata ansvariga. Global radering granskas alltid av TeamZone.':
        'Archiving does not hide history. Personal data erasure requires two separate administrators. Global erasure is always reviewed by TeamZone.',
    'Personer': 'People',
    'Raderingsbegäranden': 'Erasure requests',
    'Inga pågående raderingsbegäranden.': 'No pending erasure requests.',
    'Godkänn': 'Approve',
    'Matchöversikt': 'Match overview',
    'Välj alla behöriga': 'Select all eligible people',
    'Ny draft med alla behöriga': 'New draft with all eligible people',
    'Närvaro': 'Attendance',
    'Okänd och frånvarande är alltid separata statusar.':
        'Unknown and absent are always separate statuses.',
    'Truppen kunde inte sparas. Ladda om och försök igen.':
        'The squad could not be saved. Reload and try again.',
    'Ändringen kunde inte sparas. Ladda om och försök igen.':
        'The change could not be saved. Reload and try again.',
    'Eventet ändrades av någon annan. Ladda om och försök igen.':
        'The event was changed by someone else. Reload and try again.',
    'Kontrollera anslutningen och försök igen. Ingen gammal data visas som aktuell.':
        'Check your connection and try again. Stale data is not shown as current.',
    'Event från alla dina valda klubb- och lagkontexter visas här.':
        'Events from all selected club and team contexts appear here.',
    'Abonnemanget uppdateras när betalningen har bekräftats.':
        'The subscription updates after the payment is confirmed.',
    'Öppnar…': 'Opening…',
    'Välj plan': 'Choose plan',
    'Den här rollen saknar behörighet i aktuell lagkontext.':
        'This role lacks permission in the current team context.',
    'Grunden är klar. Nya planer skapas av behörig ledare.':
        'The foundation is ready. New plans are created by an authorized coach.',
    'Du saknar behörighet att utföra den här åtgärden.':
        'You do not have permission to perform this action.',
    'Kommandot kunde inte bekräftas. Kontrollera anslutningen.':
        'The command could not be confirmed. Check your connection.',
    'händelse': 'event',
    'Matchhändelser': 'Match events',
    'Dataminimerad leveranshistorik; meddelandetext visas inte här.':
        'Data-minimized delivery history; message text is not shown here.',
    'Kontaktförfrågan från TeamZone': 'Contact request from TeamZone',
    'Vid akut fara ring 112. Misstänkt brott: 114 14.':
        'In immediate danger, call 112. To report a suspected crime in Sweden, call 114 14.',
    'Ändrad i kalendern': 'Changed in calendar',
    'Pris enligt offert': 'Price by quote',
    'Kostnadsfri': 'Free',
    'Offert': 'Quote',
    'Starta andra halvlek': 'Start second half',
    'Halvtid': 'Half-time',
    'Kort': 'Card',
    'Byte': 'Substitution',
    'Skada': 'Injury',
  };
  String get signOut => isSwedish ? 'Logga ut' : 'Sign out';
  String eventOwner(String name) =>
      isSwedish ? '$name (ägare)' : '$name (owner)';
  String selectedParticipants(int count) =>
      isSwedish ? '$count valda deltagare' : '$count selected participants';
  String callupSummary(int total, int accepted, int pending) => isSwedish
      ? '$total skickade · $accepted accepterade · $pending väntar'
      : '$total sent · $accepted accepted · $pending pending';
  String registeredParticipants(int count) => isSwedish
      ? '$count registrerade deltagare'
      : '$count participants recorded';
  String get viewParticipantsAndResponses => isSwedish
      ? 'Visa deltagare och mina svar'
      : 'View participants and my responses';
  String get manageEventParticipation => isSwedish
      ? 'Hantera urval, kallelser, svar och närvaro'
      : 'Manage selection, call-ups, responses and attendance';
  String preparationTitle(String eventType) => switch (eventType) {
    'match' => isSwedish ? 'Matchförberedelser' : 'Match preparation',
    'training' => isSwedish ? 'Träningsförberedelser' : 'Training preparation',
    'meeting' => isSwedish ? 'Mötesförberedelser' : 'Meeting preparation',
    _ => isSwedish ? 'Förberedelser' : 'Preparation',
  };
  String preparationDescription(String eventType) => eventType == 'match'
      ? (isSwedish
            ? 'Planera trupp, taktik och matchgenomförande i Match Space.'
            : 'Plan the squad, tactics and match delivery in Match Space.')
      : (isSwedish
            ? 'Samla deltagare och uppdatera eventets information före genomförandet.'
            : 'Gather participants and update the event information before it starts.');
  String matchSpaceAction(bool v2) => v2
      ? (isSwedish ? 'Öppna Match Space' : 'Open Match Space')
      : (isSwedish ? 'Öppna matchöversikt' : 'Open match overview');
  String get followUpUnavailable => isSwedish
      ? 'Uppföljningsuppgifter är inte tillgängliga för din roll.'
      : 'Follow-up information is not available for your role.';
  String attendanceSummary(int recorded, int total) => isSwedish
      ? '$recorded av $total närvarostatusar registrerade.'
      : '$recorded of $total attendance statuses recorded.';
  String welcome(String name) => name.isEmpty
      ? (isSwedish ? 'Välkommen' : 'Welcome')
      : (isSwedish ? 'Välkommen, $name' : 'Welcome, $name');
  String get waitingRoom => isSwedish
      ? 'Ditt konto är klart men saknar ännu en aktiv klubb- eller lagrelation. Här kommer du senare kunna hantera inbjudningar och ansökningar.'
      : 'Your account is ready but does not yet have an active club or team relationship. Invitations and requests will be handled here later.';
  String destination(String path) => switch (path) {
    '/home' => isSwedish ? 'Hem' : 'Home',
    '/team' => isSwedish ? 'Laget' : 'Team',
    '/calendar' => isSwedish ? 'Kalender' : 'Calendar',
    '/inbox' => 'Inbox',
    '/statistics' => isSwedish ? 'Statistik' : 'Statistics',
    '/development' => isSwedish ? 'Utveckling' : 'Development',
    _ => '',
  };
  String get surfaceReady => isSwedish
      ? 'Ytan är säkert förberedd. Domäninnehåll kommer i en senare slice.'
      : 'This surface is safely prepared. Domain content arrives in a later slice.';
  String get couldNotLoad =>
      isSwedish ? 'Kunde inte hämta innehållet' : 'Could not load content';
  String get safeError => isSwedish
      ? 'Kontrollera anslutningen och försök igen.'
      : 'Check your connection and try again.';
  String get offlineData => isSwedish
      ? 'Visar senast verifierade data'
      : 'Showing last verified data';
  String lastUpdated(DateTime value) => isSwedish
      ? 'Uppdaterad ${value.toLocal()}'
      : 'Updated ${value.toLocal()}';
  String get upcomingEvents =>
      isSwedish ? 'Kommande aktiviteter' : 'Upcoming events';
  String get pendingCallups =>
      isSwedish ? 'Kallelser att svara på' : 'Call-ups awaiting response';
  String get pendingNotifications =>
      isSwedish ? 'Väntande aviseringar' : 'Pending notifications';
  String get inboxEmpty => isSwedish ? 'Inkorgen är tom' : 'The inbox is empty';
  String get messagesLater => isSwedish
      ? 'Meddelanden aktiveras i en senare slice.'
      : 'Messages will be enabled in a later slice.';
  String get inboxSafeEmpty => isSwedish
      ? 'Du har inga trådar i den här kontexten.'
      : 'You have no threads in this context.';
  String get newMessage => isSwedish ? 'Nytt meddelande' : 'New message';
  String get noAllowedRecipients => isSwedish
      ? 'Det finns inga tillåtna mottagare i den här kontexten.'
      : 'There are no allowed recipients in this context.';
  String get chooseRecipient =>
      isSwedish ? 'Välj mottagare' : 'Choose recipient';
  String get directMessage => isSwedish ? 'Direktmeddelande' : 'Direct message';
  String get noMessages =>
      isSwedish ? 'Inga meddelanden ännu' : 'No messages yet';
  String get muteThread =>
      isSwedish ? 'Ändra aviseringar' : 'Change notifications';
  String get messageBody => isSwedish ? 'Meddelande' : 'Message';
  String get sendMessage => isSwedish ? 'Skicka meddelande' : 'Send message';
  String get recalledMessage =>
      isSwedish ? 'Meddelandet har återkallats' : 'This message was recalled';
  String get noStatistics => isSwedish
      ? 'Ingen närvarostatistik ännu'
      : 'No attendance statistics yet';
  String get statisticsEmpty => isSwedish
      ? 'Statistik visas när närvaro har registrerats.'
      : 'Statistics appear after attendance is recorded.';
  String get present => isSwedish ? 'Närvarande' : 'Present';
  String get late => isSwedish ? 'Sen' : 'Late';
  String get partial => isSwedish ? 'Delvis' : 'Partial';
  String get absent => isSwedish ? 'Frånvarande' : 'Absent';
  String get unknown => isSwedish ? 'Ej registrerad' : 'Not recorded';
  String nextEventAt(DateTime value) => isSwedish
      ? 'Nästa aktivitet ${value.toLocal()}'
      : 'Next event ${value.toLocal()}';
  String action(String value) => switch (value) {
    'create_event' => isSwedish ? 'Skapa aktivitet' : 'Create event',
    'manage_roster' => isSwedish ? 'Hantera trupp' : 'Manage roster',
    'manage_squad' => isSwedish ? 'Hantera uttagning' : 'Manage squad',
    'record_attendance' =>
      isSwedish ? 'Registrera närvaro' : 'Record attendance',
    _ => isSwedish ? 'Öppna' : 'Open',
  };
  String get pageNotFound => isSwedish ? 'Sidan finns inte' : 'Page not found';
  String get linkNotAvailable => isSwedish
      ? 'Länken kunde inte öppnas i den här versionen av TeamZone.'
      : 'The link could not be opened in this version of TeamZone.';
}
