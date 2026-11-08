// The help section's questions: account and payment, and technical ones.
// Prices and terms as lib/tactics/access.ts and the product page have them.
import type { QuestionGroup } from "./model.ts";

export const questionGroups: QuestionGroup[] = [
  {
    id: "betalning",
    title: { sv: "Konto och betalning", en: "Account and payment" },
    questions: [
      {
        id: "provperiod",
        q: { sv: "Hur fungerar provperioden?", en: "How does the free trial work?" },
        a: [
          { sv: "Du får prova Tacticsboard gratis i 7 dagar från det att du skapar kontot. Du behöver inte ange något kort.", en: "You can try Tacticsboard free for 7 days from when you create your account. You don't need to give a card." },
          { sv: "Köper du en prenumeration under provperioden betalar du först när provperioden är slut.", en: "If you subscribe during the trial, you pay only when the trial ends." },
        ],
      },
      {
        id: "pris",
        q: { sv: "Vad kostar det?", en: "What does it cost?" },
        a: [
          { sv: "39 kr i månaden eller 390 kr om året, inklusive moms. Året motsvarar två gratis månader jämfört med månadspriset.", en: "39 SEK a month or 390 SEK a year, including VAT. The year is two months free compared with the monthly price." },
          { sv: "Köper du årsprenumerationen senast 31 december 2026 får du 25 % rabatt första året: 292,50 kr. Därefter gäller 390 kr om året.", en: "Buy the yearly plan by 31 December 2026 and you get 25 % off the first year: 292.50 SEK. After that it is 390 SEK a year." },
        ],
      },
      {
        id: "betalsatt",
        q: { sv: "Hur betalar jag?", en: "How do I pay?" },
        a: [
          { sv: "Med kort, Apple Pay eller Google Pay. Betalningen sker hos Stripe; vi ser aldrig dina kortuppgifter.", en: "By card, Apple Pay or Google Pay. Payment is handled by Stripe; we never see your card details." },
        ],
      },
      {
        id: "kvitton",
        q: { sv: "Var hittar jag mina kvitton, och hur byter jag kort?", en: "Where are my receipts, and how do I change card?" },
        a: [
          { sv: "Gå till Konto och välj Hantera betalning och kvitton. Där, hos Stripe, ser du dina kvitton, byter kort och säger upp prenumerationen.", en: "Go to Account and choose Manage payment and receipts. There, at Stripe, you see your receipts, change card and cancel the subscription." },
        ],
      },
      {
        id: "saga-upp",
        q: { sv: "Hur säger jag upp prenumerationen?", en: "How do I cancel the subscription?" },
        a: [
          { sv: "Under Konto, Hantera betalning och kvitton, när du vill. Prenumerationen gäller perioden ut, och du kan använda Tacticsboard till dess.", en: "Under Account, Manage payment and receipts, whenever you like. The subscription runs to the end of the period, and you can use Tacticsboard until then." },
        ],
      },
      {
        id: "angra",
        q: { sv: "Kan jag ångra köpet?", en: "Can I withdraw from the purchase?" },
        a: [
          { sv: "Ja, i 14 dagar från köpet. Välj Ångra köpet på kontosidan och bekräfta med ditt namn. Prenumerationen avslutas direkt.", en: "Yes, for 14 days from the purchase. Choose Withdraw from purchase on the account page and confirm with your name. The subscription ends at once." },
          { sv: "Har du betalat får du tillbaka pengarna inom 14 dagar, med avdrag för en proportionell del av priset för den tid du har använt. Ett mottagningsbevis skickas till din e-post.", en: "If you have paid, you get the money back within 14 days, less a proportional part of the price for the time you have used. A receipt of your withdrawal is sent to your e-mail." },
        ],
      },
      {
        id: "last",
        q: { sv: "Vad händer när provperioden eller prenumerationen tar slut?", en: "What happens when the trial or the subscription ends?" },
        a: [
          { sv: "Tacticsboard låses tills du prenumererar. Inget tas bort: dina projekt finns kvar och fungerar igen så fort du har betalat.", en: "Tacticsboard is locked until you subscribe. Nothing is deleted: your projects are kept and work again as soon as you have paid." },
          { sv: "Länkar och mappar du har delat fortsätter att fungera för dem du delat med.", en: "Links and folders you have shared keep working for those you shared them with." },
        ],
      },
      {
        id: "teamzone",
        q: { sv: "Behöver jag vara med i TeamZone?", en: "Do I need to be in TeamZone?" },
        a: [
          { sv: "Nej. Du skapar ett konto med din e-post och ett lösenord och kan börja direkt. Har du ett lag i TeamZone kan du koppla projekt till laget, men det behövs inte.", en: "No. You create an account with your e-mail and a password and can start right away. If you have a team in TeamZone you can link projects to it, but you don't have to." },
        ],
      },
      {
        id: "losenord",
        q: { sv: "Jag har glömt lösenordet.", en: "I have forgotten my password." },
        a: [
          { sv: "Välj Glömt lösenordet? på inloggningssidan. Du får en länk till din e-post där du väljer ett nytt lösenord. Hittar du inte mejlet, titta i skräpposten.", en: "Choose Forgot your password? on the sign-in page. You get a link by e-mail where you choose a new password. If you can't find the e-mail, look in your spam folder." },
        ],
      },
      {
        id: "avsluta-konto",
        q: { sv: "Hur tar jag bort mitt konto?", en: "How do I delete my account?" },
        a: [
          { sv: "Under Konto finns Avsluta kontot för gott. Kontot och allt du gjort i Tacticsboard tas bort: projekt, mappar, mallar, delade länkar och det du publicerat i biblioteket. Det går inte att ångra.", en: "Under Account there is Delete my account for good. The account and everything you have made in Tacticsboard is deleted: projects, folders, templates, shared links and what you have published in the library. It cannot be undone." },
          { sv: "En pågående prenumeration avslutas direkt, utan återbetalning för resten av perioden. Dina kvitton finns kvar hos Stripe.", en: "A running subscription ends at once, without a refund for the rest of the period. Your receipts stay at Stripe." },
        ],
      },
      {
        id: "support",
        q: { sv: "Hur når jag supporten?", en: "How do I reach support?" },
        a: [
          { sv: "Mejla {email}. Vi svarar inom två vardagar.", en: "E-mail {email}. We reply within two working days." },
        ],
      },
    ],
  },
  {
    id: "teknik",
    title: { sv: "Teknik och felsökning", en: "Technical questions" },
    questions: [
      {
        id: "enheter",
        q: { sv: "Vilka enheter och webbläsare fungerar?", en: "Which devices and browsers work?" },
        a: [
          { sv: "Tacticsboard körs i webbläsaren, på dator, surfplatta och telefon. Använd en aktuell version av Chrome, Edge, Safari eller Firefox. Du behöver inte installera något.", en: "Tacticsboard runs in the browser, on computer, tablet and phone. Use an up-to-date Chrome, Edge, Safari or Firefox. There is nothing to install." },
          { sv: "På telefon ligger verktygen på planen och panelerna öppnas ovanpå den, så att planen får så mycket plats som möjligt. Störst nytta har du av en dator eller surfplatta när du bygger större övningar.", en: "On a phone the tools sit on the pitch and the panels open over it, so the pitch gets as much room as possible. A computer or tablet is handiest for building larger drills." },
        ],
      },
      {
        id: "spara",
        q: { sv: "Hur sparas det jag gör?", en: "How is my work saved?" },
        a: [
          { sv: "Automatiskt, en kort stund efter varje ändring. Tappar du uppkopplingen ligger en kopia kvar i webbläsaren tills den har sparats, och försöker du lämna sidan med osparade ändringar får du en fråga först.", en: "Automatically, a moment after each change. If you lose the connection, a copy stays in the browser until it has been saved, and if you try to leave the page with unsaved changes you are asked first." },
          { sv: "Har samma projekt ändrats någon annanstans under tiden, till exempel i en annan flik, skrivs inget över. Du kan hämta den senaste versionen, eller spara dina ändringar som en kopia.", en: "If the same project has been changed elsewhere meanwhile, say in another tab, nothing is overwritten. You can get the latest version, or save your changes as a copy." },
        ],
      },
      {
        id: "versioner",
        q: { sv: "Kan jag gå tillbaka till en tidigare version?", en: "Can I go back to an earlier version?" },
        a: [
          { sv: "Ja. Under Versioner i projektet sparas tidigare versioner, högst en per halvtimme du arbetar, och alltid innan någon annan sparar över eller innan du återställer. Den som äger projektet kan visa och återställa dem. Även återställningen går att ångra.", en: "Yes. Under Versions in the project, earlier versions are kept, at most one per half hour of work, and always before someone else saves over it or before you restore. The project's owner can view and restore them. A restore can be undone too." },
          { sv: "För enstaka ändringar finns Ångra och Gör om (Ctrl + Z och Ctrl + Y).", en: "For single changes there are Undo and Redo (Ctrl + Z and Ctrl + Y)." },
        ],
      },
      {
        id: "lankar",
        q: { sv: "Behöver de jag delar med ett konto?", en: "Do the people I share with need an account?" },
        a: [
          { sv: "Nej. Den som får en delad länk kan titta och spela upp tavlorna utan konto, alltid som de senast sparades. Länken fungerar tills du tar bort den under Dela.", en: "No. Anyone with a shared link can watch and play the boards without an account, always as last saved. The link works until you revoke it under Share." },
        ],
      },
      {
        id: "video",
        q: { sv: "Videon blir en WebM-fil, eller knappen för video saknas.", en: "The video is a WebM file, or the video button is missing." },
        a: [
          { sv: "Videon spelas in i webbläsaren. Kan den spela in MP4 blir det MP4, annars WebM, som de flesta spelare och sociala medier också klarar. Saknar webbläsaren stöd för inspelning visas inte knappen; prova då i Chrome eller Edge på en dator.", en: "The video is recorded in the browser. If it can record MP4 you get MP4, otherwise WebM, which most players and social media also handle. If the browser cannot record at all, the button is not shown; then try Chrome or Edge on a computer." },
          { sv: "Låt fliken vara öppen och synlig medan videon spelas in.", en: "Keep the tab open and visible while the video is recorded." },
        ],
      },
      {
        id: "live",
        q: { sv: "Hur många kan vara med på en livelektion?", en: "How many can join a live lesson?" },
        a: [
          { sv: "Upp till 12 deltagare. De ansluter med en kod, en länk eller en QR-kod i mobilen och följer tavlan som du visar den. De kan inte ändra något.", en: "Up to 12 participants. They join with a code, a link or a QR code on their phone and follow the board as you show it. They cannot change anything." },
          { sv: "Lektionen avslutas av sig själv efter 30 minuter utan aktivitet.", en: "The lesson ends by itself after 30 minutes without activity." },
        ],
      },
      {
        id: "fil",
        q: { sv: "Kan jag flytta ett projekt till ett annat konto?", en: "Can I move a project to another account?" },
        a: [
          { sv: "Ja. Under Dela kan du spara projektet som fil. Filen importeras på startsidan, även på ett annat konto, som ett nytt eget projekt. Kopplingar till spelare i ett TeamZone-lag följer inte med.", en: "Yes. Under Share you can save the project as a file. The file is imported on the start page, also on another account, as a new project of your own. Links to players in a TeamZone team do not come along." },
        ],
      },
      {
        id: "sprak",
        q: { sv: "Hur byter jag språk?", en: "How do I change language?" },
        a: [
          { sv: "Med språkvalet längst ner på sidorna, och i sidhuvudet innan du har loggat in. Tacticsboard finns på svenska och engelska.", en: "With the language choice at the foot of the pages, and in the header before you have signed in. Tacticsboard is in Swedish and English." },
        ],
      },
      {
        id: "fel",
        q: { sv: "Något fungerar inte som det ska.", en: "Something doesn't work as it should." },
        a: [
          { sv: "Ladda om sidan först; det du gjort är sparat. Hjälper det inte, mejla {email} och berätta vad du gjorde, vilken enhet och webbläsare du använder, och gärna en skärmbild.", en: "Reload the page first; your work is saved. If that doesn't help, e-mail {email} and tell us what you did, which device and browser you use, and a screenshot if you can." },
        ],
      },
    ],
  },
];
