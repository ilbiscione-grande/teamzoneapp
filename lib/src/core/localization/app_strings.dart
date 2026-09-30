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
  String get offlineNotice => isSwedish
      ? 'Du är offline. Nytt innehåll kan inte hämtas.'
      : 'You are offline. New content cannot be loaded.';
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
  String peopleCount(int count) =>
      isSwedish ? '$count personer' : '$count people';
  String participantCount(int count) =>
      isSwedish ? 'Antal deltagare: $count' : 'Participants: $count';
  String calendarFrom(String period) =>
      isSwedish ? 'Från $period' : 'From $period';
  String contactPerson(String name) =>
      isSwedish ? 'Kontakta $name' : 'Contact $name';
  String contactRequestFrom(String name) =>
      isSwedish ? 'Kontaktförfrågan från $name' : 'Contact request from $name';
  String contactIssue(String reason) =>
      isSwedish ? 'Ärende: $reason' : 'Subject: $reason';
  String contactExpires(String date) =>
      isSwedish ? 'Gäller till $date' : 'Valid until $date';
  String contactReasonLabel(String code) => switch (code) {
    'match' => feature('Match'),
    'event' => feature('Event'),
    'transfer' => feature('Spelarövergång'),
    'club_business' => feature('Klubbärende'),
    'other' => feature('Annat'),
    _ => feature('Övrigt ärende'),
  };
  String selectedRecipients(int count) =>
      isSwedish ? 'Valda mottagare: $count' : 'Selected recipients: $count';
  String inboxGroupTitle(String title) => switch (title) {
    'Flera lag' || 'Övriga konversationer' || 'Flera klubbar' => feature(title),
    _ => title,
  };
  String movePlayersAction(int count) =>
      isSwedish ? 'Flytta $count spelare' : 'Move $count players';
  String playerMoveResult(int moved, int failed) {
    if (failed == 0) {
      if (moved == 1) return feature('Spelaren är flyttad.');
      return isSwedish
          ? '$moved spelare är flyttade.'
          : '$moved players have been moved.';
    }
    if (moved == 0) {
      return feature(
        'Ingen spelare kunde flyttas. Ladda om och kontrollera datum och lag.',
      );
    }
    return isSwedish
        ? '$moved spelare flyttades. $failed kunde inte flyttas.'
        : '$moved players were moved. $failed could not be moved.';
  }

  String eligibilityKind(String value) => switch (value) {
    'team_assignment' =>
      isSwedish ? 'Ordinarie lagtrupp' : 'Regular team roster',
    'development' => isSwedish ? 'Utvecklingsspelare' : 'Development player',
    'dispensation' => isSwedish ? 'Dispens' : 'Dispensation',
    'loan' => isSwedish ? 'Lån' : 'Loan',
    'guest' => isSwedish ? 'Gäst' : 'Guest',
    'cross_team' => isSwedish ? 'Annat lag' : 'Other team',
    _ => value,
  };
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
    'in_review' => isSwedish ? 'Granskas' : 'In review',
    'resolved' => isSwedish ? 'Löst' : 'Resolved',
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
    'Återaktivera i laget': 'Reactivate in team',
    'Event': 'Event',
    'Spelarövergång': 'Player transfer',
    'Klubbärende': 'Club matter',
    'Övrigt ärende': 'Other matter',
    'Arkiverade': 'Archived',
    'Flytta till lag': 'Move to team',
    'Åtgärder': 'Actions',
    'Flytta till ett annat lag': 'Move to another team',
    'Medlemsuppgifter': 'Member details',
    'Medlemsdetaljen är inte tillgänglig': 'Member details are unavailable',
    'Spelaren är arkiverad.': 'The player is archived.',
    'Vald dag': 'Selected day',
    'Hela månaden': 'Entire month',
    'Inga event denna månad': 'No events this month',
    'Kommande event': 'Upcoming events',
    'Inga kommande event': 'No upcoming events',
    'Byt kalendervy': 'Change calendar view',
    'Välj datum': 'Select date',
    'Välj startdatum för agendan': 'Select agenda start date',
    'Träningstema': 'Training theme',
    'Träningsplan': 'Training plan',
    'Motståndare *': 'Opponent *',
    'Hemmaplan eller bortaplan': 'Home or away',
    'Hemma': 'Home',
    'Borta': 'Away',
    'Matchanteckningar': 'Match notes',
    'Syfte': 'Purpose',
    'Mötesagenda': 'Meeting agenda',
    'Typ av event': 'Event type',
    'Samling före start (minuter)': 'Meet before start (minutes)',
    'Serien börjar': 'Series starts',
    'Serien slutar': 'Series ends',
    'Hitta extern kontakt': 'Find external contact',
    'Klubb, lag eller ledare': 'Club, team or leader',
    'Lämna tomt för att visa alla tillåtna kontakter.':
        'Leave blank to show all permitted contacts.',
    'Verifierade ledarkontakter': 'Verified leader contacts',
    'Anledning till kontakt': 'Reason for contact',
    'Ytterligare information (valfritt)': 'Additional information (optional)',
    'Beskriv kort vad du vill kontakta ledaren om.':
        'Briefly explain why you want to contact the leader.',
    'Verifierad ledare': 'Verified leader',
    'Ange en rubrik.': 'Enter a subject.',
    'Välj minst en mottagare.': 'Select at least one recipient.',
    'Flera lag': 'Multiple teams',
    'Övriga konversationer': 'Other conversations',
    'Byte av ordinarie lag': 'Change of regular team',
    'Åldersanpassning': 'Age-group adjustment',
    'Omorganisation inom klubben': 'Club reorganization',
    'Flytt beslutad av lagansvarig': 'Move decided by team manager',
    'Ingen spelare kunde flyttas. Ladda om och kontrollera datum och lag.':
        'No player could be moved. Reload and check the date and teams.',
    'Ansök': 'Apply',
    'Ansök som': 'Apply as',
    'Ange ett klubbnamn med 2–120 tecken.':
        'Enter a club name containing 2–120 characters.',
    'Ange ett lagnamn med 1–120 tecken.':
        'Enter a team name containing 1–120 characters.',
    'Ansökan kunde inte skickas.': 'The application could not be sent.',
    'Ansökan kunde inte återkallas.': 'The application could not be withdrawn.',
    'Du har redan en väntande ansökan för den rollen. Vänta på svar eller dra tillbaka ansökan.':
        'You already have a pending application for that role. Wait for a response or withdraw the application.',
    'Ansökningarna kunde inte hämtas.': 'The applications could not be loaded.',
    'Ansökningarna kunde inte hämtas': 'The applications could not be loaded',
    'Avslå': 'Reject',
    'Avslå medlemsansökan?': 'Reject membership application?',
    'Beslutet kunde inte sparas. Ladda om och försök igen.':
        'The decision could not be saved. Reload and try again.',
    'Godkänn medlemsansökan?': 'Approve membership application?',
    'Godkänn som': 'Approve as',
    'Ansökt som: {role}': 'Applied as: {role}',
    'Hitta klubb eller lag': 'Find a club or team',
    'Sök, ansök eller hantera väntande ansökningar.':
        'Search, apply, or manage pending applications.',
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
    'Gör klubben officiell': 'Make the club official',
    'Ansök hos TeamZone om att verifiera klubben.':
        'Apply to TeamZone to verify the club.',
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
    'Kontakta TeamZone': 'Contact TeamZone',
    'Ärendet skickas till TeamZones supportadministratörer.':
        'The case is sent to TeamZone support administrators.',
    'Meddelande': 'Message',
    'Nytt anslag': 'New announcement',
    'Anslag': 'Announcement',
    'Behöver din uppmärksamhet': 'Needs your attention',
    'Viktigt anslag': 'Important announcement',
    'Information': 'Information',
    'Arkiverade anslag': 'Archived announcements',
    'Anslaget är avslutat och kan inte få fler meddelanden.':
        'The announcement is complete and cannot receive more messages.',
    'Skriv ett meddelande.': 'Write a message.',
    'Välj minst en målgrupp.': 'Select at least one audience.',
    'Målgrupp': 'Audience',
    'Omfattning': 'Scope',
    'Laget': 'The team',
    'Hela klubben': 'Entire club',
    'Anslaget skickas till laget.':
        'The announcement will be sent to the team.',
    'Det finns inga aktiva mottagare i den valda målgruppen.':
        'There are no active recipients in the selected audience.',
    'Du saknar behörighet att skicka anslaget i vald omfattning.':
        'You do not have permission to send the announcement to the selected scope.',
    'Kontrollera rubrik, meddelande och målgrupp och försök igen.':
        'Check the subject, message and audience and try again.',
    'Anslaget kunde inte skickas. Serverkod: {code}':
        'The announcement could not be sent. Server code: {code}',
    'Anslaget kunde inte skickas. Kontrollera anslutningen och försök igen.':
        'The announcement could not be sent. Check the connection and try again.',
    'Skicka': 'Send',
    'Ange ett meddelande med 20–1000 tecken.':
        'Enter a message containing 20–1000 characters.',
    'Skicka ärende': 'Submit case',
    'Ärendet kunde inte skickas. Försök igen.':
        'The case could not be submitted. Please try again.',
    'Ärendet är skickat. TeamZone granskar uppgifterna och återkommer i appen.':
        'The case has been submitted. TeamZone will review the details and respond in the app.',
    'Supportärenden': 'Support cases',
    'Kontoradering · hög risk': 'Account erasure · high risk',
    'Skyddat klubbnamn': 'Protected club name',
    'Påbörja granskning': 'Start review',
    'Lös ärende': 'Resolve case',
    'Avslå ärende': 'Reject case',
    'Beslutsanteckning': 'Decision note',
    'Ange minst 5 tecken.': 'Enter at least 5 characters.',
    'Spara beslut': 'Save decision',
    'Ärendet kunde inte uppdateras. Läs om kön och försök igen.':
        'The case could not be updated. Reload the queue and try again.',
    'Supportkön är inte tillgänglig': 'The support queue is unavailable',
    'Du saknar supportbehörighet eller så kunde kön inte laddas.':
        'You do not have support access or the queue could not be loaded.',
    'Inga supportärenden i vald status.':
        'There are no support cases with the selected status.',
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
    'Användarvillkor': 'Terms of service',
    'Integritetspolicy': 'Privacy policy',
    'Filtrera händelser': 'Filter events',
    'Alla händelser': 'All events',
    'Kommande händelser': 'Upcoming events',
    'Tidigare händelser': 'Previous events',
    'Resultat': 'Result',
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
    'Färgtema': 'Color theme',
    'Färgen är själva temat — resten av utseendet är samma '
            'oavsett vilken du väljer.':
        "The color is the theme — everything else looks the same no "
        'matter which you pick.',
    'Grön': 'Green',
    'Blå': 'Blue',
    'Röd': 'Red',
    'Orange': 'Orange',
    'Genvägar': 'Shortcuts',
    'Planera aktivitet': 'Plan an activity',
    'Hantera laget': 'Manage the team',
    'Öppna inkorgen': 'Open the inbox',
    'Skapa nytt event': 'Create a new event',
    'Bjud in spelare': 'Invite a player',
    'Skicka meddelande': 'Send a message',
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
    'Lagbild': 'Team image',
    'Välj lagbild': 'Choose team image',
    'Byt lagbild': 'Change team image',
    'Ta bort lagbild': 'Remove team image',
    'JPG, PNG eller WebP. Max 5 MB. Originalet lagras privat.':
        'JPG, PNG or WebP. Max 5 MB. The original is stored privately.',
    'Bilden måste vara högst 5 MB.': 'The image must be no larger than 5 MB.',
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
    'Kommer': 'Attending',
    'Obesvarad': 'Awaiting response',
    'Din kallelse': 'Your callup',
    'Svara': 'Respond',
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
    'Ägande lag': 'Owning team',
    'Delat med detta lag': 'Shared with this team',
    'Ägande lag – eventet administreras härifrån':
        'Owning team – the event is managed from here',
    'Lag som eventet kan delas med': 'Teams this event can be shared with',
    'Du kan dela eventet med flera lag samtidigt.':
        'You can share the event with several teams at the same time.',
    'Delat event': 'Shared event',
    'Dela med laget': 'Share with this team',
    'Standard: Kan se': 'Default: Can view',
    'Rättighet': 'Permission',
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
    'Förhandsgranska utkast': 'Preview draft',
    'Föreslås från rubriken. Du kan ändra adressen.':
        'Suggested from the headline. You can change the address.',
    'Föreslå adress från rubriken': 'Suggest address from headline',
    'Endast förhandsgranskning i appen. Inget har sparats eller publicerats.':
        'Preview in the app only. Nothing has been saved or published.',
    'Rubrik saknas': 'Headline missing',
    'Artikeltext saknas': 'Article text missing',
    'Valda publiceringskanaler': 'Selected publishing channels',
    'Ingen kanal vald': 'No channel selected',
    'Saknas': 'Missing',
    'Utkastet kunde inte sparas. Försök igen eller kontakta support.':
        'The draft could not be saved. Try again or contact support.',
    'Klubbsidan är inte publicerad. Aktivera klubbens publika sida innan du publicerar nyheter.':
        'The club page is not published. Activate the public club page before publishing news.',
    'Publiceringen kunde inte genomföras. Ladda om och försök igen.':
        'Publishing could not be completed. Reload and try again.',
    'Spara ändringarna i utkastet innan du publicerar.':
        'Save your draft changes before publishing.',
    'Publicera nyheten?': 'Publish this article?',
    'Använd 2–100 tecken: små bokstäver, siffror och bindestreck.':
        'Use 2–100 characters: lowercase letters, numbers and hyphens.',
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
    'Födelseår': 'Birth year',
    'Födelsedatum': 'Date of birth',
    'Välj födelsedatum': 'Select date of birth',
    'Välj år, månad och dag': 'Select year, month and day',
    'Välj ett födelsedatum.': 'Select a date of birth.',
    'Välj ett födelseår.': 'Select a birth year.',
    'Lägg till fullständigt datum': 'Add full date of birth',
    'Ta bort exakt datum': 'Remove exact date',
    'Tillbaka till truppen': 'Back to roster',
    'Spelare från andra lag kunde inte laddas. Försök igen.':
        'Players from other teams could not be loaded. Try again.',
    'Det finns inga aktiva spelare i klubbens andra lag.':
        'There are no active players in the club’s other teams.',
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
    'Mina lagkopplingar': 'My team connections',
    'Här ser du vilka lag och roller du är kopplad till, och kan lägga till en ny koppling med en inbjudan eller lagkod.':
        'Here you can see which teams and roles you are connected to, and add a new connection with an invitation or team code.',
    'Du har inga lagkopplingar ännu.': 'You have no team connections yet.',
    'Dina kopplingar': 'Your connections',
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
    'Tidigare inbjudningar': 'Previous invitations',
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
    'Aktivt lag': 'Active team',
    'Byt till': 'Switch to',
    'Lägg till ett nytt lag i den aktiva klubben.':
        'Add a new team to the active club.',
    'Skicka en förfrågan till klubbens administratör.':
        'Send a request to the club administrator.',
    'Förfrågningar om nya lag': 'New team requests',
    'Förfrågan är skickad till klubbens administratör.':
        'The request was sent to the club administrator.',
    'Förfrågningarna kunde inte laddas.': 'The requests could not be loaded.',
    'Inga förfrågningar.': 'No requests.',
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
    'Stäng TeamZone?': 'Close TeamZone?',
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
    'Meddelandet skickades inte eftersom du inte längre har tillgång till konversationen. Kopiera texten innan du stänger.':
        'The message was not sent because you no longer have access to this conversation. Copy the text before closing.',
    'Skickar…': 'Sending…',
    'Fästa': 'Pinned',
    'Inställningar': 'Settings',
    'Öppna menyn': 'Open menu',
    'Byt lag eller roll': 'Switch team or role',
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
    'Skicka sena kallelser': 'Send late call-ups',
    'Spara': 'Save',
    'Spara närvaro': 'Save attendance',
    'Aldrig kallad': 'Never called up',
    'Eventdetaljer kunde inte laddas': 'Event details could not load',
    'Fler åtgärder': 'More actions',
    'Gäst': 'Guest',
    'Gästspelare': 'Guest players',
    'Kallade': 'Called up',
    'Kallade ledare': 'Called-up coaches',
    'Kallade spelare': 'Called-up players',
    'Kunde inte uppdatera. Försök igen.': 'Could not update. Try again.',
    'Obesvarade': 'Unanswered',
    'Okallade ledare': 'Not called-up coaches',
    'Okallade spelare': 'Not called-up players',
    'Registrera eller granska närvaro': 'Record or review attendance',
    'Utkast': 'Draft',
    'Deltog': 'Attended',
    'Sparat.': 'Saved.',
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
    'Eventet är inställt': 'The event is cancelled',
    'Information och historik finns kvar, men eventet genomförs inte.':
        'Information and history remain available, but the event will not take place.',
    'Eventet måste vara inställt eller genomfört innan det kan arkiveras.':
        'The event must be cancelled or completed before it can be archived.',
    'Arkiverade event': 'Archived events',
    'Visa arkiverade event': 'Show archived events',
    'Döljer aktiva event och visar den bevarade historiken.':
        'Hides active events and shows the retained history.',
    'Historiken är bevarad. Öppna ett event för att visa eller återställa det.':
        'The history is retained. Open an event to view or restore it.',
    'Inga arkiverade event': 'No archived events',
    'Arkiverade event för det valda laget visas här.':
        'Archived events for the selected team appear here.',
    'Arkiverad': 'Archived',
    'Eventet är arkiverat': 'The event is archived',
    'Eventet är skrivskyddat men historiken finns kvar.':
        'The event is read-only, but its history remains available.',
    'Återställ från arkiv': 'Restore from archive',
    'Eventet återgår till kalendern med samma status som före arkiveringen.':
        'The event returns to the calendar with the same status it had before archiving.',
    'Eventet har återställts.': 'The event has been restored.',
    'Eventet kunde inte återställas.': 'The event could not be restored.',
    'Välj behörighetsgrupp': 'Select eligibility group',
    'Generera deltagarurval': 'Generate participant selection',
    'Ordinarie spelare prioriteras och urvalet blir alltid reproducerbart.':
        'Regular players are prioritized and the selection is always reproducible.',
    'Använd urval': 'Use selection',
    'Alla behöriga': 'All eligible people',
    'Behörighetsgrupp': 'Eligibility group',
    'Skapa ett balanserat, reproducerbart urval':
        'Create a balanced, reproducible selection',
    'Deltagarurvalet kunde inte sparas. Ladda om och försök igen.':
        'The participant selection could not be saved. Reload and try again.',
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
    'Filtrera kalendern': 'Filter the calendar',
    'Veckonummer': 'Week number',
    'Visa veckonummer': 'Show week number',
    'Visa kvartsmarkeringar': 'Show quarter-hour marks',
    'Extra tunna linjer var 15:e minut i dagsvyn.':
        'Extra thin lines every 15 minutes in the day view.',
    'Nästa period': 'Next period',
    'Inga event i vald vy': 'No events in the selected view',
    'Byt datum eller justera filtren.':
        'Change the date or adjust the filters.',
    'Byt månad eller justera filtren.':
        'Change the month or adjust the filters.',
    'Inga event den här dagen.': 'No events on this day.',
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
    'Påmind': 'Reminded',
    'Avböjt': 'Declined',
    'Svara som vårdnadshavare': 'Respond as guardian',
    'Svara som ledare': 'Respond as leader',
    'Minuter': 'Minutes',
    'Påminnelsen är skickad.': 'The reminder has been sent.',
    'Kallelsen är återkallad.': 'The call-up has been withdrawn.',
    'Rosteråtgärder': 'Roster actions',
    'Truppen kunde inte laddas.': 'The squad could not be loaded.',
    'Träning': 'Training',
    'År': 'Year',
    'Återkalla': 'Recall',
    'Åtgärden har lagts till.': 'The action was added.',
    'Åtgärden kunde inte sparas. Försök igen.':
        'The action could not be saved. Please try again.',
    'Ändringen är sparad.': 'The change was saved.',
    'Ansökan är skickad till klubben och väntar på beslut.':
        'The request was sent to the club and is awaiting a decision.',
    'Ansökan är godkänd. Välj lagets synlighet för att publicera sidan.':
        'The request was approved. Select the team visibility to publish the page.',
    'Ansökan är avslagen.': 'The request was rejected.',
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
    'Rensa filter': 'Clear filter',
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
    'Avsluta en lagtillhörighet med namngiven historik eller begär skyddad anonymisering.':
        'End a team assignment with named history or request protected anonymization.',
    'Arkivera från laget': 'Archive from team',
    'Avsluta i laget': 'End team membership',
    'Personen flyttas till Tidigare. Historiska fakta bevaras.':
        'The person is moved to Previous. Historical facts are preserved.',
    'Personen flyttas till Arkiverade. Namn, matcher, närvaro och annan historik bevaras.':
        'The person is moved to Archived. Their name, matches, attendance and other history are preserved.',
    'Begär radering av klubbuppgifter': 'Request erasure of club data',
    'Begär anonymisering': 'Request anonymization',
    'En annan klubbansvarig måste godkänna. Namn och lokala personuppgifter anonymiseras, men verksamhetshistorik bevaras.':
        'Another club administrator must approve. The name and local personal data are anonymized, while operational history is preserved.',
    'Raderingsbegäran kunde inte skapas.':
        'The erasure request could not be created.',
    'Anonymiseringsbegäran kunde inte skapas. Kontrollera om det redan finns en väntande begäran för personen.':
        'The anonymization request could not be created. Check whether a pending request already exists for this person.',
    'Godkänn anonymisering': 'Approve anonymization',
    'Du måste vara en annan klubbansvarig än den som startade begäran. Åtgärden kan inte ångras i appen.':
        'You must be a different club administrator from the requester. The action cannot be undone in the app.',
    'Du måste vara en annan klubbansvarig än den som startade begäran. Namnet och personens egna rekord anonymiseras permanent. Lagets historiska fakta bevaras.':
        'You must be a different club administrator from the requester. The name and personal records are permanently anonymized. The team historical facts are preserved.',
    'Godkännandet nekades. Kontrollera behörighet och att initiatorn är en annan användare.':
        'Approval was denied. Check permission and that the requester is another user.',
    'Laddar livscykel': 'Loading lifecycle',
    'Livscykeln kunde inte laddas': 'The lifecycle could not be loaded',
    'Arkivering döljer inte historik. Personuppgiftsradering kräver två separata ansvariga. Global radering granskas alltid av TeamZone.':
        'Archiving does not hide history. Personal data erasure requires two separate administrators. Global erasure is always reviewed by TeamZone.',
    'Avsluta i laget bevarar namn och historik. Anonymisering tar bort identiteten och kräver två separata ansvariga. Global kontoradering granskas alltid av TeamZone.':
        'Ending team membership preserves the name and history. Anonymization removes the identity and requires two separate administrators. Global account erasure is always reviewed by TeamZone.',
    'Personer': 'People',
    'Raderingsbegäranden': 'Erasure requests',
    'Anonymiseringsbegäranden': 'Anonymization requests',
    'Inga pågående raderingsbegäranden.': 'No pending erasure requests.',
    'Inga pågående anonymiseringsbegäranden.':
        'No pending anonymization requests.',
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
    'Tillbaka': 'Back',
    'Nästa': 'Next',
    'Bekräfta och skapa': 'Confirm and create',
    'Bjud in ny spelare': 'Invite new player',
    'Koppla vårdnadshavare': 'Link guardian',
    'Aktiva inbjudningar och koder': 'Active invitations and codes',
    'Vem gäller inbjudan?': 'Who is this invitation for?',
    'Välj vad du vill skapa. Nästa steg förklarar vad som händer '
            'innan något skapas.':
        'Choose what to create. The next step explains what happens '
        'before anything is created.',
    'Skicka en personlig länk till en vald rosterpost via e-post.':
        'Send a personal link to a chosen roster entry by email.',
    'En delbar kod som flera kan använda för att ansöka om en roll.':
        'A shareable code several people can use to apply for a role.',
    'En riktad inbjudan skickas till en specifik person via e-post och '
            'kopplas till en vald rosterpost. Mottagaren öppnar länken, '
            'verifierar sin e-post och kontot binds automatiskt till rätt '
            'person i laget. Länken fungerar en gång och är giltig i 7 dagar. '
            'TeamZone skickar inte länken automatiskt — du delar den själv.':
        'A targeted invitation is sent to a specific person by email and '
        'linked to a chosen roster entry. The recipient opens the link, '
        'verifies their email, and the account is bound to the right '
        'person in the team automatically. The link works once and is '
        'valid for 7 days. TeamZone does not send the link '
        'automatically — you share it yourself.',
    'Inga barn i truppen är markerade som i behov av '
            'vårdnadshavarkoppling än. Öppna barnets personuppgifter och slå '
            'på "Behöver vårdnadshavarkoppling" innan du fortsätter här.':
        'No children in the roster are marked as needing a guardian link '
        'yet. Open the child\'s details and turn on "Needs guardian '
        'link" before continuing here.',
    'En guardian-koppling länkar en vuxen som redan finns i laget '
            'till ett barn som är markerat som i behov av '
            'vårdnadshavarkoppling. Efter att koden använts kan '
            'vårdnadshavaren se information och svara på kallelser för '
            'barnets räkning.':
        'A guardian link connects an adult already in the team to a child '
        'marked as needing a guardian. Once the code is used, the '
        'guardian can see information and respond to callups on the '
        'child\'s behalf.',
    'En lagkod är en delbar kod som flera personer kan använda för '
            'att ansöka om en vald roll i laget. En behörig ledare granskar '
            'ändå varje ansökan innan personen läggs till. Koden är giltig i '
            '30 dagar och kan användas upp till 100 gånger.':
        'A team code is a shareable code several people can use to apply '
        'for a chosen role in the team. An authorized leader still '
        'reviews every application before the person is added. The '
        'code is valid for 30 days and can be used up to 100 times.',
    'Dela koden fritt — den kan användas flera gånger fram till '
            'utgångsdatumet.':
        'Share the code freely — it can be used several times until it '
        'expires.',
    'Dela koden med mottagaren. De klistrar in den under '
            'Inställningar → Använd kod.':
        'Share the code with the recipient. They paste it under '
        'Settings → Use code.',
    'Du bjuder in': 'You are inviting',
    'att gå med som': 'to join as',
    'Du kopplar': 'You are linking',
    'som vårdnadshavare till': 'as guardian to',
    'Du skapar en lagkod för rollen':
        'You are creating a team code for the role',
    'Publika sidor': 'Public pages',
    'Länka en vuxen till ett barn som redan finns i truppen.':
        'Link an adult to a child already in the roster.',
    'Alla aktiva personer i truppen har redan ett kopplat konto. '
            'Lägg till en ny person i truppen om du vill bjuda in någon '
            'ytterligare.':
        'Everyone active in the roster already has a linked account. Add '
        'a new person to the roster if you want to invite someone '
        'else.',
    'Tillåt representation i andra lag': 'Allow representing other teams',
    'Gör personen valbar när ett annat lag i klubben '
            'vill be om representation. Ingen börjar '
            'representera automatiskt -- ditt lag godkänner '
            'varje sådan begäran för sig.':
        'Makes the person selectable when another team in the club wants '
        'to request representation. No one starts representing '
        'automatically -- your team approves each such request on '
        'its own.',
    'begärd av': 'requested by',
    'från': 'from',
    'Bjud in': 'Invite',
    'Skicka en inbjudan så personen kan koppla ett konto.':
        'Send an invitation so the person can link an account.',
    'Representation i annat lag': 'Representation on another team',
    'Föreslå personen för ett annat lag i klubben.':
        'Propose the person to another team in the club.',
    'Slå på "Tillåt representation i andra lag" under Redigera person '
            'innan du fortsätter här.':
        'Turn on "Allow representing other teams" under Edit person '
        'before continuing here.',
    'Lagen kunde inte laddas. Försök igen.':
        'The teams could not be loaded. Try again.',
    'Förfrågan skickad. Ditt lag behöver godkänna den innan '
            'det andra laget kan använda spelaren.':
        'Request sent. Your team needs to approve it before the other '
        'team can use the player.',
    'Förfrågan kunde inte sparas. Kontrollera lag, period och överlapp.':
        'The request could not be saved. Check team, period and overlap.',
    'Redigera profil': 'Edit profile',
    'Ändra uppgifter och hantera lag- och kontoåtgärder.':
        'Change details and manage team and account actions.',
    'Statistik': 'Statistics',
    'Träningsnärvaro': 'Training attendance',
    'Matcher spelade': 'Matches played',
    'Statistiken kunde inte laddas': 'The statistics could not be loaded',
    'Skapa en ny klubb': 'Create a new club',
    'Starta en helt separat klubb med ett första lag.':
        'Start a completely separate club with a first team.',
    'Klubben har skapats.': 'The club has been created.',
    'Allmänt': 'General',
    'Profil': 'Profile',
    'Standardvy för kalendern': 'Default calendar view',
    'Vilken vy kalendern öppnas i. Utan ett val visas månadsvyn.':
        'Which view the calendar opens in. Month view shows without a choice.',
    'Filtrera inkorgen': 'Filter the inbox',
    'Lag och klubbar': 'Teams and clubs',
    'Visar aktivt lag som standard. Välj fler för att '
            'se deras konversationer också.':
        'Shows the active team by default. Pick more to see their '
        'conversations too.',
    'Du kan inte ändra eller ta bort din egen ledarroll.':
        'You can\'t change or remove your own leader role.',
    'Personen spelar i ett annat lag. Använd Flytta eller Representation.':
        'This person plays in another team. Use Move or Representation.',
    'Rollen har redan ändrats av någon annan.':
        'The role was already changed by someone else.',
    'Rollen kunde inte ändras. Försök igen.':
        'The role couldn\'t be changed. Try again.',
    'du': 'you',
    'Ledare och roller': 'Leaders and roles',
    'Inga ledare ännu': 'No leaders yet',
    'är nu ledare i laget.': 'is now a leader of the team.',
    'Ledare kan hantera truppen, kallelser och event i laget.':
        'Leaders can manage the squad, call-ups and events for the team.',
    'Rollerna kunde inte laddas.': 'The roles couldn\'t be loaded.',
    'Lägg till ledare': 'Add leader',
    'Ändra roll': 'Change role',
    'är nu spelare i laget.': 'is now a player in the team.',
    'är inte längre ledare i laget.': 'is no longer a leader of the team.',
    'Ändra till spelare': 'Change to player',
    'Ta bort som ledare': 'Remove as leader',
    'Sök person': 'Search person',
    'Klubbens ledare': 'Club\'s leaders',
    'Klubbens ledare kunde inte laddas.':
        'The club\'s leaders couldn\'t be loaded.',
    'Alla klubbens ledare är redan ledare här.':
        'All of the club\'s leaders already lead this team.',
    'Från truppen': 'From the squad',
    'Ingen i truppen att välja.': 'No one in the squad to choose.',
    'Behåller sin spelarroll': 'Keeps their player role',
    'Ny person': 'New person',
    'Bjud in med en lagkod': 'Invite with a team code',
    'Skapa en lagkod med rollen Ledare under Inbjudningar och lagkoder.':
        'Create a team code with the Leader role under Invitations and team codes.',
    'Lägg till ledarroll': 'Add leader role',
    'Byt från spelare till ledare': 'Switch from player to leader',
    'Byt från ledare till spelare': 'Switch from leader to player',
    'Ta bort ledarrollen': 'Remove leader role',
    'Roll i laget': 'Role in the team',
    'Ingen roll': 'No role',
    'Lägg till ledare, även dig själv eller klubbens befintliga ledare.':
        'Add leaders, including yourself or the club\'s existing leaders.',
    'Uppgifterna kunde inte hämtas. Kontrollera din behörighet och försök igen.':
        'The details couldn\'t be loaded. Check your permissions and try again.',
    'Uppgifterna har ändrats av någon annan. Hämta senaste uppgifter innan du sparar.':
        'Someone else changed these details. Load the latest before saving.',
    'Kunde inte spara. Kontrollera anslutningen och din behörighet och försök igen.':
        'Couldn\'t save. Check your connection and permissions and try again.',
    'Titel och position': 'Title and position',
    'Position': 'Position',
    'Gäller i detta lag och ändrar inte personens behörigheter.':
        'Applies to this team and doesn\'t change the person\'s permissions.',
    'Egen titel': 'Own title',
    'Egen position': 'Own position',
    'detaljerat': 'detailed',
    'Hämta senaste uppgifter': 'Load latest details',
    'Kunde inte hämta uppgifterna': 'Couldn\'t load the details',
    'Hämtar uppgifter…': 'Loading details…',
    'Inga valda': 'None selected',
    'Välj titel': 'Choose title',
    'Ingen titel vald': 'No title chosen',
    'Idrott': 'Sport',
    'Styr vilka spelarpositioner som finns att välja.':
        'Determines which playing positions can be chosen.',
    'Huvudtränare': 'Head coach',
    'Assisterande tränare': 'Assistant coach',
    'Lagledare': 'Team manager',
    'Kontaktperson': 'Contact person',
    'Målvaktstränare': 'Goalkeeper coach',
    'Fystränare': 'Fitness coach',
    'Materialansvarig': 'Equipment manager',
    'Medicinskt ansvarig': 'Medical staff',
    'Kassör': 'Treasurer',
    'Administratör': 'Administrator',
    'Målvakt': 'Goalkeeper',
    'Försvarare': 'Defender',
    'Mittfältare': 'Midfielder',
    'Anfallare': 'Forward',
    'Mittback': 'Centre back',
    'Vänsterback': 'Left back',
    'Högerback': 'Right back',
    'Wingback': 'Wing back',
    'Defensiv mittfältare': 'Defensive midfielder',
    'Central mittfältare': 'Central midfielder',
    'Offensiv mittfältare': 'Attacking midfielder',
    'Vänsterytter': 'Left winger',
    'Högerytter': 'Right winger',
    'Centralanfallare': 'Striker',
    'Nia': 'Back court',
    'Kant': 'Wing',
    'Linjespelare': 'Pivot',
    'Vänsternia': 'Left back',
    'Mittnia': 'Centre back',
    'Högernia': 'Right back',
    'Vänstersexa': 'Left wing',
    'Högersexa': 'Right wing',
    'Fotboll': 'Football',
    'Handboll': 'Handball',
    'Annan idrott': 'Other sport',
    'Övrigt': 'Other',
    'Trupp och medlemmar': 'Squad and members',
    'Lägga till, ändra och bjuda in personer': 'Add, edit and invite people',
    'Ledare och behörigheter': 'Leaders and permissions',
    'Göra personer till ledare och ändra behörigheter':
        'Make people leaders and change permissions',
    'Skapa och flytta event': 'Create and move events',
    'Datum, tid, plats, ställa in och dela':
        'Date, time, place, cancel and share',
    'Kallelser': 'Call-ups',
    'Välja trupp, skicka och påminna': 'Pick the squad, send and remind',
    'Sen närvarorättelse': 'Late attendance correction',
    'Rätta närvaro efter att eventet är över':
        'Correct attendance after the event',
    'Material, uppgifter och filer': 'Equipment, tasks and files',
    'Förberedelser som alla behöver, mötesagenda':
        'Shared preparations, meeting agenda',
    'Träningsupplägg': 'Training plan',
    'Träningsfokus och träningsanteckningar':
        'Training focus and training notes',
    'Matchplan och taktik': 'Match plan and tactics',
    'Matchförberedelse och taktik': 'Match preparation and tactics',
    'Matchläge och resultat': 'Match mode and result',
    'Klocka, mål, resultat och matchrapport':
        'Clock, goals, result and match report',
    'Spelarutveckling': 'Player development',
    'Utvecklingsplaner': 'Development plans',
    'Nyheter och lagets publika sida': 'News and the team\'s public page',
    'Målvakts- och fystränare': 'Goalkeeper and fitness coach',
    'Ledare (standard)': 'Leader (standard)',
    'Anpassad': 'Custom',
    'Utgå från mall': 'Start from template',
    'Anpassad – skiljer sig från mallarna':
        'Custom – differs from the templates',
    'Vissa behörigheter ändrades inte eftersom du själv saknar dem.':
        'Some permissions weren\'t changed because you don\'t have them yourself.',
    'Titeln föreslår mallen': 'The title suggests the template',
    'Använd': 'Use',
    'Behörigheterna har ändrats av någon annan. Stäng och öppna igen.':
        'Someone else changed the permissions. Close and open again.',
    'Du kan bara ge eller ta bort behörigheter som du själv har.':
        'You can only give or remove permissions you have yourself.',
    'Du kan inte ta bort din egen behörighet att hantera ledare.':
        'You can\'t remove your own permission to manage leaders.',
    'Laget måste ha minst en person som kan hantera ledare.':
        'The team needs at least one person who can manage leaders.',
    'Behörigheterna kunde inte sparas. Försök igen.':
        'The permissions couldn\'t be saved. Try again.',
    'Behörighet': 'Permission',
    'Behörigheter': 'Permissions',
    'Behörigheterna sparades för': 'Permissions saved for',
    'Nya ledare och behörigheter hanteras av huvudtränaren eller en klubbfunktionär.':
        'New leaders and permissions are managed by the head coach or a club functionary.',
    'Titlar, behörigheter och nya ledare':
        'Titles, permissions and new leaders',
    'Klubbfunktionär – hela klubben': 'Club functionary – whole club',
    'Inga spelare i truppen ännu.': 'No players in the squad yet.',
    'Du har ingen profil i det här laget': 'You have no profile in this team',
    'Byt till ett lag där du är spelare eller ledare, eller se dina kontouppgifter under Inställningar.':
        'Switch to a team where you are a player or leader, or see your account details under Settings.',
    'Min profil': 'My profile',
    'Sökningen kunde inte laddas. Lagets deltagare visas fortfarande.':
        'Search could not be loaded. The team\'s participants are still shown.',
    'Kallelserna är skickade.': 'The callups have been sent.',
    'Kallelserna är skickade, men listan kunde inte uppdateras. Öppna eventet igen.':
        'The callups were sent, but the list could not be updated. Open the event again.',
    'Kallelserna kunde inte bekräftas. Försök igen med samma urval.':
        'The callups could not be confirmed. Try again with the same selection.',
    'Antal minuter sen': 'Minutes late',
    'Antal minuter närvarande': 'Minutes present',
    'Minuter (1–1440)': 'Minutes (1–1440)',
    'Registrera högst 100 personer åt gången.':
        'Record at most 100 people at a time.',
    'Ange en orsak till den sena ändringen (3–500 tecken).':
        'Give a reason for the late change (3–500 characters).',
    'Närvaron är sparad, men listan kunde inte uppdateras. Öppna eventet igen.':
        'Attendance was saved, but the list could not be updated. Open the event again.',
    'Närvaron kunde inte sparas. Listan kan ha ändrats. Ladda om innan du försöker igen.':
        'Attendance could not be saved. The list may have changed. Reload before trying again.',
    'Åtgärden kunde inte utföras. Ladda om och försök igen.':
        'The action could not be completed. Reload and try again.',
    'Svaret kunde inte sparas. Ladda om och försök igen.':
        'The response could not be saved. Reload and try again.',
    'Några påminnelser kunde inte skickas. Ladda om och försök igen.':
        'Some reminders could not be sent. Reload and try again.',
    'Sök deltagare i klubben': 'Search participants in the club',
    'Välj alla spelare': 'Select all players',
    'Påminn alla obesvarade': 'Remind everyone who has not answered',
    'Markera accepterade som närvarande': 'Mark accepted as present',
    'Behörighet kunde inte hämtas. Försök igen':
        'Permissions could not be loaded. Try again',
    'Markera återstående som frånvarande': 'Mark remaining as absent',
    'valda': 'selected',
    'Kalla': 'Call up',
    'Orsak till sen ändring': 'Reason for late change',
    'ändringar': 'changes',
    'kallade': 'called',
    'svarat': 'answered',
    'Avmarkera alla': 'Deselect all',
    'Markera alla': 'Select all',
    'Sen': 'Late',
    'Delvis närvarande': 'Partly present',
    'Ej registrerad': 'Not recorded',
    'Avmarkera': 'Deselect',
    'Välj': 'Select',
    'Påminn · senast': 'Remind · last',
    'Ej svarat': 'Not answered',
    'Accepterat': 'Accepted',
    'Kallelse': 'Callup',
    'Dölj information om': 'Hide information about',
    'Visa information om': 'Show information about',
    'Närvarostatistik är inte tillgänglig.':
        'Attendance statistics are not available.',
    'Född': 'Born',
    'Du svarar som vårdnadshavare': 'You are answering as guardian',
    'Senaste påminnelse': 'Last reminder',
    'Återkalla kallelse': 'Withdraw callup',
    'Inbjudningar och förfrågningar': 'Invitations and requests',
    'Nästa händelse': 'Next event',
    'Senaste match': 'Latest match',
    'Idrotten ändras av klubbens administratörer.':
        'The sport is changed by the club administrators.',
    'Om laget': 'About the team',
    'Händelserna kunde inte laddas.': 'Events could not be loaded.',
    'Inga kommande händelser.': 'No upcoming events.',
    'Inga spelade matcher ännu.': 'No matches played yet.',
    'Vy och filter': 'View and filters',
    'Vy': 'View',
    'Flera klubbar': 'Several clubs',
    'Nytt meddelande': 'New message',
    'Sök mottagare': 'Search recipients',
    'Välj en eller flera mottagare': 'Choose one or more recipients',
    'Direktmeddelande': 'Direct message',
    'Gruppkonversation': 'Group conversation',
    'Starta konversation': 'Start conversation',
    'Skapa grupp': 'Create group',
    'Inga mottagare matchar sökningen.': 'No recipients match the search.',
    'Ta bort {name}': 'Remove {name}',
    'Visa konversationer': 'Show conversations',
    'Dölj konversationer': 'Hide conversations',
    'olästa': 'unread',
    'Ange ett gruppnamn.': 'Enter a group name.',
    'Om du accepterar kan ni starta en privat konversation i TeamZone.':
        'If you accept, you can start a private conversation in TeamZone.',
    'Meddelandeförhandsvisningar visas bara här för chattar du har tillgång till.':
        'Message previews are only shown here for chats you have access to.',
    'Konversationen döljs bara för dig. Övriga deltagare och historiken påverkas inte.':
        'The conversation is hidden only for you. Other participants and the history are not affected.',
    'Du lämnar konversationen. Tidigare meddelanden finns kvar för övriga deltagare.':
        'You leave the conversation. Earlier messages remain for the other participants.',
    'Båda': 'Both',
    'Personen lades till, men roll, titel eller position kunde inte sparas. Ändra det på personens profil.':
        'The person was added, but the role, title or position could not be saved. Change it on the person\'s profile.',
    'Ange motståndare.': 'Enter the opponent.',
    'Motståndarens namn är för långt.': 'The opponent name is too long.',
    'Sluttiden måste vara efter starttiden.':
        'The end time must be after the start time.',
    'Samlingen ska vara 0–1440 minuter före start.':
        'Gathering must be 0–1440 minutes before the start.',
    'Ange en tidszon.': 'Enter a time zone.',
    'Kontrollera serien: 2–104 tillfällen och ett intervall på 1–52.':
        'Check the series: 2–104 occurrences and an interval of 1–52.',
    'När': 'When',
    'Från': 'From',
    'Till': 'To',
    'Datum': 'Date',
    'Samling kl.': 'Gathering at',
    'Skapar ett event per tillfälle.': 'Creates one event per occurrence.',
    'T.ex. konstgräsplanen': 'E.g. the artificial pitch',
    'Detaljer': 'Details',
    'Spara som utkast': 'Save as draft',
    'Planeras klart och publiceras senare.':
        'Finish planning and publish later.',
    'Fler inställningar': 'More settings',
    'dag': 'day',
    'vecka': 'week',
    '{count} tillfällen': '{count} occurrences',
    'Anläggning': 'Facility',
    'T.ex. Bergby IP': 'E.g. Bergby sports ground',
    'Plan (valfritt)': 'Pitch (optional)',
    'T.ex. Plan 3': 'E.g. Pitch 3',
    'Underlag (valfritt)': 'Surface (optional)',
    'T.ex. konstgräs': 'E.g. artificial grass',
    'Ange anläggning för planen och underlaget.':
        'Enter the facility for the pitch and surface.',
    'Kontrollera e-postadressen.': 'Check the email address.',
    'Telefonnumret får bara innehålla siffror, mellanslag, bindestreck och +.':
        'The phone number may only contain digits, spaces, hyphens and +.',
    'Profilen har ändrats någon annanstans. Öppna den igen.':
        'The profile was changed elsewhere. Open it again.',
    'Du har redan en begäran som inte är klar.':
        'You already have a request that is not finished.',
    'Det är redan din inloggningsadress.':
        'That is already your login address.',
    'Det gick inte att spara. Försök igen.': 'Could not save. Try again.',
    'Bilden får vara högst 2 MB.': 'The picture may be at most 2 MB.',
    'Ange ditt namn.': 'Enter your name.',
    'Begäran är skickad. Supporten återkommer innan något ändras.':
        'The request was sent. Support gets back to you before anything changes.',
    'Kolla din e-post': 'Check your email',
    'Vi har skickat en bekräftelselänk till {email}. Bytet gäller när du har bekräftat.':
        'We sent a confirmation link to {email}. The change applies once you confirm.',
    'Bekräftelsen kunde inte skickas. Försök igen om en stund.':
        'The confirmation could not be sent. Try again in a while.',
    'Väntar på support: byte till {email}.':
        'Waiting for support: change to {email}.',
    'Godkänt: bekräfta bytet till {email}.':
        'Approved: confirm the change to {email}.',
    'Den senaste begäran avslogs.': 'The latest request was declined.',
    'Inloggningsadress': 'Login address',
    'Bekräfta bytet': 'Confirm the change',
    'Avbryt begäran': 'Cancel request',
    'Begär byte av inloggningsadress': 'Request a new login address',
    'Av säkerhetsskäl granskar supporten varje byte. Därefter bekräftar du via en länk i e-posten.':
        'For security, support reviews every change. Then you confirm with a link in the email.',
    'Mina uppgifter': 'My details',
    'Profilen kunde inte laddas': 'The profile could not be loaded',
    'Byt bild': 'Change picture',
    'Lägg till bild': 'Add picture',
    'Ta bort bild': 'Remove picture',
    'Kontakt-e-post': 'Contact email',
    'Telefon': 'Phone',
    'Kontaktuppgifterna visas bara för dig och ledarna i dina lag. Profilbilden syns för alla i dina klubbar.':
        'Contact details are shown only to you and the leaders of your teams. Your picture is visible to everyone in your clubs.',
    'Beskriv varför med minst 5 tecken.':
        'Describe why in at least 5 characters.',
    'Byt inloggningsadress': 'Change login address',
    'Supporten granskar begäran. När den är godkänd bekräftar du bytet via en länk som skickas till den nya adressen.':
        'Support reviews the request. Once approved, you confirm the change with a link sent to the new address.',
    'Ny inloggningsadress': 'New login address',
    'Varför vill du byta?': 'Why do you want to change?',
    'Skicka till support': 'Send to support',
    'Namn saknas': 'Name missing',
    'Lägg till kontaktuppgifter': 'Add contact details',
    'E-post': 'Email',
    'Ingen angiven': 'None given',
    'Inget angivet': 'None given',
    'Ifyllt av klubben.': 'Filled in by the club.',
    'Redigera mina uppgifter': 'Edit my details',
    'Namn, kontaktuppgifter och profilbild.':
        'Name, contact details and picture.',
    'Ändra kontaktuppgifter': 'Change contact details',
    'Personen har inget konto, så klubben fyller i uppgifterna.':
        'The person has no account, so the club fills in the details.',
    'Kontaktuppgifter': 'Contact details',
    'Godkänn byte': 'Approve change',
    'Avslå byte': 'Decline change',
    'T.ex. hur identiteten kontrollerades.':
        'E.g. how the identity was checked.',
    'Beslutet kunde inte sparas. Ladda om.':
        'The decision could not be saved. Reload.',
    'Byte av inloggningsadress': 'Login address changes',
    'Kön kunde inte laddas.': 'The queue could not be loaded.',
    'Inga väntande begäranden.': 'No pending requests.',
    'Kontrollera adressen och postnumret.':
        'Check the address and postal code.',
    'Gatuadress': 'Street address',
    'Postnummer': 'Postal code',
    'Ort': 'City',
    'Adress': 'Address',
    'Visa medlemskort': 'Show member card',
    'Klubbmärke': 'Club badge',
    'Visas på klubbens medlemskort.': 'Shown on the club member cards.',
    'Medlemskortet kunde inte laddas.': 'The member card could not be loaded.',
    'Visa framsidan': 'Show the front',
    'Visa baksidan': 'Show the back',
    'MEDLEMSKORT': 'MEMBER CARD',
    'Roll': 'Role',
    'Vårdnadshavare till': 'Guardian of',
    'Medlems-ID': 'Member ID',
    'Medlem sedan': 'Member since',
    'Adress och kontaktuppgifter visas bara för personen och lagets ledare.':
        'Address and contact details are shown only to the person and the team leaders.',
    'Ingen adress angiven': 'No address given',
    'Klubbmärket får vara högst 1 MB.': 'The club badge may be at most 1 MB.',
    'Klubbmärket kunde inte sparas.': 'The club badge could not be saved.',
    'Klubbmärket kunde inte tas bort.': 'The club badge could not be removed.',
    'Visas på medlemskorten för alla i klubben. PNG, JPG eller WebP, högst 1 MB.':
        'Shown on the member cards for everyone in the club. PNG, JPG or WebP, at most 1 MB.',
    'Välj bild': 'Choose image',
    'Markera som läst': 'Mark as read',
    'Ta bort notisen': 'Remove notification',
    'Medlemsinfo': 'Member info',
    'Statistik visas för personen själv och lagets ledare.':
        'Statistics are shown to the person and the team leaders.',
    'Träning och match': 'Training and matches',
    'Mål': 'Goals',
    'Assist': 'Assists',
    'Mottagna': 'Received',
    'Tackat ja': 'Accepted',
    'Tackat nej': 'Declined',
    'Snittid för svar': 'Average response time',
    'Appen': 'The app',
    'Dagar i rad': 'Days in a row',
    'Längsta svit': 'Longest streak',
    'Aktiva dagar (30 d)': 'Active days (30 d)',
    'Skickade meddelanden': 'Messages sent',
    'Appanvändning visas bara för personen själv.':
        'App use is shown only to the person.',
    'dygn': 'days',
    'Presentation': 'Presentation',
    'T.ex. Flicklag': 'E.g. Girls team',
    'T.ex. F2012': 'E.g. F2012',
    'Vilka ni är, var ni tränar och vad som gäller för laget.':
        'Who you are, where you train and what applies to the team.',
    'Tryck för att välja lagbild': 'Tap to choose a team picture',
    'Lagprofilen kunde inte sparas. Försök igen.':
        'The team profile could not be saved. Try again.',
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
  String selectAllPlayersLabel(int count) => count == 0
      ? (isSwedish ? 'Alla spelare valda' : 'All players selected')
      : (isSwedish
            ? 'Välj alla spelare ($count)'
            : 'Select all players ($count)');
  String remindAllUnansweredLabel(int count) => count == 0
      ? (isSwedish ? 'Alla har svarat' : 'Everyone has answered')
      : (isSwedish
            ? 'Påminn alla obesvarade ($count)'
            : 'Remind everyone unanswered ($count)');
  String markAllPresentLabel(int count) => isSwedish
      ? 'Sätt alla accepterade som deltog ($count)'
      : 'Mark everyone who accepted as attended ($count)';
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
  String lastUpdated(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final formatted =
        '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
    return isSwedish ? 'Uppdaterad $formatted' : 'Updated $formatted';
  }

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
