// Guides, second part: animating, presenting, sharing and exporting, live
// lessons, keeping projects in order, and the team and the library.
import type { Guide } from "./model.ts";

export const showGuides: Guide[] = [
  {
    slug: "animera",
    title: { sv: "Animera med frames", en: "Animating with frames" },
    summary: { sv: "Bygg ett förlopp steg för steg och spela upp det.", en: "Build a sequence step by step and play it." },
    sections: [
      {
        title: { sv: "Frames", en: "Frames" },
        steps: [
          { sv: "Tryck + under planen. Den nya framen är en kopia av den du står på.", en: "Tap + below the pitch. The new frame is a copy of the one you are on." },
          { sv: "Flytta spelarna och bollen dit de ska. Tryck ▶ för att se rörelsen mellan dina frames.", en: "Move the players and the ball where they should go. Tap ▶ to see the movement between your frames." },
          { sv: "Välj en frame med siffrorna under planen, eller med ← och → på tangentbordet.", en: "Choose a frame with the numbers below the pitch, or with ← and → on the keyboard." },
        ],
      },
      {
        title: { sv: "Tid och rörelse", en: "Time and motion" },
        text: { sv: "För varje frame väljer du hur lång tid förflyttningen dit tar och hur den rör sig: mjuk, jämn, mjuk start eller mjukt stopp. Uppspelningen kan gå i slinga och i olika hastighet. Under Frames skriver du också en anteckning till varje frame, som visas i PDF:en och i visningsläget.", en: "For each frame you choose how long the move into it takes and how it moves: smooth, even, smooth start or smooth stop. Playback can loop and run at different speeds. Under Frames you also write a note for each frame, shown in the PDF and when presenting." },
      },
      {
        title: { sv: "Effekter", en: "Effects" },
        text: { sv: "Markera ett objekt och välj en effekt under Frames: tona in, poppa fram, rita fram, puls, lys upp, spår, pil, markera, strålkastare eller zooma. Effekten spelas när tavlan går in i framen, så den finns från frame 2.", en: "Select an object and choose an effect under Frames: fade in, pop, draw, pulse, highlight, trail, arrow, mark, spotlight or zoom. The effect plays as the board moves into the frame, so it is there from frame 2." },
        tip: { sv: "Nya objekt tonar in och borttagna tonar ut av sig själva.", en: "New objects fade in and removed ones fade out by themselves." },
      },
    ],
  },
  {
    slug: "visa",
    title: { sv: "Visa och presentera", en: "Showing and presenting" },
    summary: { sv: "Helskärm, 3D, utsnitt och planens utseende.", en: "Full screen, 3D, crop and the pitch's look." },
    sections: [
      {
        title: { sv: "Visa i helskärm", en: "Show full screen" },
        text: { sv: "Visningsläget visar tavlan ensam på hela skärmen med beskrivningen och framens anteckning bredvid. Bläddra med knapparna eller piltangenterna, och lämna med Esc.", en: "Presenting shows the board alone on the whole screen with its description and the frame's note beside it. Step through with the buttons or the arrow keys, and leave with Esc." },
      },
      {
        title: { sv: "3D", en: "3D" },
        text: { sv: "3D visar planen snett från läktaren, som på tv. Du redigerar uppifrån; 3D är till för att visa.", en: "3D shows the pitch at an angle from the stand, as on television. You edit from above; 3D is for showing." },
      },
      {
        title: { sv: "Utsnitt", en: "Crop" },
        text: { sv: "Under Dela väljer du en del av planen att visa. Utsnittet gäller i PDF, video, visningsläget och delade länkar.", en: "Under Share you choose a part of the pitch to show. The crop applies in the PDF, video, presenting and shared links." },
      },
      {
        title: { sv: "Planen och lagen", en: "The pitch and the teams" },
        text: { sv: "Under Inställningar väljer du planens utseende och omgivning, lagens namn och färger, om spelarnas namn, positioner och blickriktning visas, och om bollen fäster vid spelare.", en: "Under Settings you choose the pitch's look and surroundings, the teams' names and colours, whether the players' names, positions and facing show, and whether the ball sticks to players." },
      },
    ],
  },
  {
    slug: "dela",
    title: { sv: "Dela och exportera", en: "Sharing and exporting" },
    summary: { sv: "Länkar, PDF, video och projektet som fil.", en: "Links, PDF, video and the project as a file." },
    sections: [
      {
        title: { sv: "Länk att titta på", en: "A link to watch" },
        text: { sv: "Under Dela skapar du en länk till hela projektet eller till tavlan du står på. Den som har länken tittar och spelar upp utan konto. Skicka den via telefonens delning, e-post, sms eller WhatsApp, eller visa den som QR-kod. Länken fungerar tills du tar bort den.", en: "Under Share you create a link to the whole project or the board you are on. Whoever has the link watches and plays without an account. Send it through your phone's sharing, e-mail, text or WhatsApp, or show it as a QR code. The link works until you revoke it." },
      },
      {
        title: { sv: "PDF", en: "PDF" },
        text: { sv: "Tavlorna på A4 med beskrivning och anteckningar. Välj vilka tavlor, och för animerade tavlor alla frames, fyra per sida eller en per sida, bara sista framen, eller hela förloppet på en bild med pilar. Kan också göras i 3D.", en: "The boards on A4 with description and notes. Choose which boards, and for animated ones all frames, four or one per page, only the last frame, or the whole sequence in one picture with arrows. Can be made in 3D too." },
      },
      {
        title: { sv: "Video", en: "Video" },
        text: { sv: "Spela in tavlan du står på som video: den spelas upp från början och sparas som fil. Markeringen tas bort och planen visas medan videon spelas in.", en: "Record the board you are on as a video: it plays from the start and is saved as a file. The selection is cleared and the pitch shows while it records." },
      },
      {
        title: { sv: "Fil", en: "File" },
        text: { sv: "Spara som fil sparar hela projektet. Filen importeras på startsidan, även på ett annat konto.", en: "Save as file saves the whole project. The file is imported on the start page, also on another account." },
      },
      {
        title: { sv: "Träningspass i TeamZone", en: "A training session in TeamZone" },
        text: { sv: "I ett träningsprojekt kopplat till ett lag lägger du tavlan som övning i ett av lagets kommande pass, med Lägg i ett pass under Dela.", en: "In a training project linked to a team, you add the board as a drill in one of the team's coming sessions, with Add to a session under Share." },
      },
    ],
  },
  {
    slug: "live",
    title: { sv: "Livelektioner", en: "Live sessions" },
    summary: { sv: "Gå igenom tavlan medan deltagarna följer med i mobilen.", en: "Go through the board while the participants follow on their phones." },
    sections: [
      {
        title: { sv: "Starta", en: "Start" },
        steps: [
          { sv: "Tryck Live i projektet och starta lektionen.", en: "Tap Live in the project and start the session." },
          { sv: "Deltagarna ansluter med koden, länken eller QR-koden. Upp till 12 kan vara med.", en: "The participants join with the code, the link or the QR code. Up to 12 can take part." },
        ],
      },
      {
        title: { sv: "Under lektionen", en: "During the session" },
        text: { sv: "Deltagarna följer tavlan som du visar den: tavla, frame, uppspelning och din pekare över planen. De kan inte ändra något, men kan svara på frågor, räcka upp handen och chatta.", en: "The participants follow the board as you show it: board, frame, playback and your pointer over the pitch. They cannot change anything, but can answer questions, raise their hand and chat." },
        tip: { sv: "Lektionen avslutas av sig själv efter 30 minuter utan aktivitet. Efteråt finns en sammanfattning.", en: "The session ends by itself after 30 minutes without activity. Afterwards there is a summary." },
      },
    ],
  },
  {
    slug: "projekt",
    title: { sv: "Projekt, mappar och mallar", en: "Projects, folders and templates" },
    summary: { sv: "Håll ordning på startsidan och återanvänd det du gjort.", en: "Keep order on the start page and reuse what you have made." },
    sections: [
      {
        title: { sv: "Startsidan", en: "The start page" },
        text: { sv: "Sök bland projekten på namn, tavlor och beskrivning. Fäst de du använder mest överst, och lägg projekt i mappar.", en: "Search the projects by name, boards and description. Pin the ones you use most to the top, and put projects in folders." },
      },
      {
        title: { sv: "Mappar", en: "Folders" },
        text: { sv: "En mapp kan delas med en länk. Den som har länken ser mappens projekt och spelar upp tavlorna utan konto, även projekt som läggs till senare.", en: "A folder can be shared with a link. Whoever has the link sees the folder's projects and plays the boards without an account, including projects added later." },
      },
      {
        title: { sv: "Mallar och versioner", en: "Templates and versions" },
        text: { sv: "Spara ett projekt som mall och börja nya projekt från den. Under Versioner går du tillbaka till en tidigare version av projektet.", en: "Save a project as a template and start new projects from it. Under Versions you go back to an earlier version of the project." },
      },
    ],
  },
  {
    slug: "lag-och-bibliotek",
    title: { sv: "Laget och biblioteket", en: "The team and the library" },
    summary: { sv: "Formationer, truppen från TeamZone och övningar från andra tränare.", en: "Formations, the squad from TeamZone and drills from other coaches." },
    sections: [
      {
        title: { sv: "Formationer och truppen", en: "Formations and the squad" },
        text: { sv: "Under Lag ställer du upp laget i en formation, eller skriver en egen som 3-1-4-2. Är projektet kopplat till ett lag i TeamZone hämtar du truppen och lägger ut spelarna med namn.", en: "Under Team you line the team up in a formation, or write your own such as 3-1-4-2. If the project is linked to a team in TeamZone, you fetch the squad and put the players out with their names." },
      },
      {
        title: { sv: "Biblioteket", en: "The library" },
        text: { sv: "I biblioteket finns övningar, pass och sessioner som tränare delar, och färdiga från oss. Sök, spara favoriter med stjärnan, och använd det du hittar som en kopia i ett eget projekt.", en: "The library holds drills, sessions and courses that coaches share, and ready ones from us. Search, keep favourites with the star, and use what you find as a copy in a project of your own." },
      },
      {
        title: { sv: "Publicera", en: "Publish" },
        text: { sv: "Under Dela publicerar du en tavla eller ett projekt i biblioteket, för alla eller bara för din klubb. Ditt namn visas, och andra får använda och kopiera det. Kopplingar till spelare följer aldrig med. Olämpligt innehåll kan anmälas.", en: "Under Share you publish a board or a project in the library, for everyone or only your club. Your name shows, and others may use and copy it. Ties to players never come along. Unsuitable content can be reported." },
      },
    ],
  },
];
