import { features } from "./welcome-landing";

// The launch page's words, in Swedish and English.
export const launchText = {
  sv: {
    kicker: "TeamZone · för föreningslivet",
    title: "Laget på ett ställe",
    availableNow: "Tillgänglig nu",
    comingSoon: "Kommer snart",
    choice: "Rita, animera och presentera taktik. Prova gratis i 7 dagar.",
    app: "TeamZone-appen",
    appChoice: "Kallelser, närvaro, meddelanden och en egen klubbsajt.",
    lead: "Verktyg för ledare, spelare och föräldrar i föreningslivet. Börja med Tacticsboard redan i dag.",
    tryBoard: "Prova Tacticsboard gratis",
    tryFree: "Prova gratis i 7 dagar",
    shot: "editor.png",
    shotAlt: "Tacticsboard med en taktiktavla, verktyg och tidslinje.",
    points: [
      { title: "Rita", text: "Spelare, bollar, koner, mål, pilar och ytor på en riktig plan." },
      { title: "Animera", text: "Bygg förloppet steg för steg och spela upp det." },
      { title: "Presentera", text: "Visa tavlan i helskärm, eller håll en livegenomgång där upp till 12 deltagare följer med i mobilen." },
      { title: "Dela", text: "Skicka en länk till spelare och föräldrar. De behöver inget konto för att titta." },
    ],
    features,
  },
  en: {
    kicker: "TeamZone · for grassroots sport",
    title: "The team in one place",
    availableNow: "Available now",
    comingSoon: "Coming soon",
    choice: "Draw, animate and present tactics. Try it free for 7 days.",
    app: "The TeamZone app",
    appChoice: "Call-ups, attendance, messages and a club website of your own.",
    lead: "Tools for coaches, players and parents in grassroots sport. Start with Tacticsboard today.",
    tryBoard: "Try Tacticsboard free",
    tryFree: "Try free for 7 days",
    shot: "editor-en.png",
    shotAlt: "Tacticsboard with a tactics board, tools and a timeline.",
    points: [
      { title: "Draw", text: "Players, balls, cones, goals, arrows and zones on a real pitch." },
      { title: "Animate", text: "Build the sequence step by step and play it back." },
      { title: "Present", text: "Show the board full screen, or run a live session where up to 12 participants follow on their phones." },
      { title: "Share", text: "Send a link to players and parents. They need no account to watch." },
    ],
    features: [
      { title: "Call-ups and replies", text: "Call the team to training and matches, see who is coming and remind those who have not replied. Players and parents reply with one tap, even right in the notification on Android." },
      { title: "Attendance", text: "Record attendance after the activity, with late arrivals and partial attendance. It follows the player through the season." },
      { title: "A team inbox", text: "Team and coach chats are created automatically. Write directly to a player or parent, start a group or send a message to the whole team." },
      { title: "My assistant", text: "Reminds you of unanswered call-ups, attendance not recorded and missing match results, so nothing falls through the cracks." },
      { title: "Club site and team pages", text: "The club gets its own public website with news, teams, matches and results. Every team gets a page of its own." },
      { title: "New players made easy", text: "Share a link or QR code and new players and parents fill in their contact details themselves." },
    ],
  },
} as const;
