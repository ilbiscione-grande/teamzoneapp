// Guides, first part: getting started, drawing, changing what is drawn, and
// working on a phone or tablet.
import type { Guide } from "./model.ts";

export const drawGuides: Guide[] = [
  {
    slug: "kom-igang",
    title: { sv: "Kom igång", en: "Getting started" },
    summary: { sv: "Skapa ditt första projekt och hitta runt på tavlan.", en: "Create your first project and find your way around the board." },
    sections: [
      {
        title: { sv: "Skapa ett projekt", en: "Create a project" },
        steps: [
          { sv: "Välj Nytt projekt på startsidan.", en: "Choose New project on the start page." },
          { sv: "Ge projektet ett namn och välj typ: Match, Träning eller Utbildning. Har du ett lag i TeamZone kan du koppla projektet till laget.", en: "Give the project a name and choose its kind: Match, Training or Education. If you have a team in TeamZone, you can link the project to it." },
          { sv: "Välj vad projektet börjar med: en tom tavla, färdiga tavlor eller en av dina mallar. Allt går att ändra sedan.", en: "Choose what the project starts with: an empty board, ready boards or one of your templates. Everything can be changed afterwards." },
        ],
      },
      {
        title: { sv: "Tavlor i ett projekt", en: "Boards in a project" },
        text: { sv: "Ett projekt kan ha flera tavlor, till exempel en per övning eller en per fas i matchen. Tavlorna ligger som flikar överst; på telefon väljer du tavla i listan.", en: "A project can have several boards, say one per drill or one per phase of the match. The boards sit as tabs at the top; on a phone you choose a board from the list." },
        steps: [
          { sv: "Med + Tavla lägger du till en tom tavla, en kopia av den du står på, en färdig tavla eller tavlorna från en mall.", en: "With + Board you add an empty board, a copy of the one you are on, a ready board or the boards of a template." },
          { sv: "Dubbelklicka på en flik för att byta namn. På telefon finns Byt namn och Ta bort tavlan sist i listan.", en: "Double-click a tab to rename it. On a phone, Rename and Remove the board are last in the list." },
        ],
      },
      {
        title: { sv: "Panelerna", en: "The panels" },
        text: { sv: "Till höger (på telefon längst ner) finns fyra flikar: Egenskaper för det du har markerat, Frames för animeringen, Objekt med allt på tavlan, och Lag med formationer och truppen.", en: "On the right (at the bottom on a phone) there are four tabs: Properties for what you have selected, Frames for the animation, Objects with everything on the board, and Team with formations and the squad." },
        tip: { sv: "Allt sparas automatiskt. Ångra och Gör om finns i verktygsraden och som Ctrl + Z och Ctrl + Y.", en: "Everything is saved automatically. Undo and Redo are in the top bar and as Ctrl + Z and Ctrl + Y." },
      },
    ],
  },
  {
    slug: "rita",
    title: { sv: "Placera spelare och rita", en: "Placing players and drawing" },
    summary: { sv: "Spelare, boll och utrustning, pilar, ytor och mått.", en: "Players, ball and equipment, arrows, areas and measures." },
    sections: [
      {
        title: { sv: "Placera", en: "Place" },
        text: { sv: "Under Placera finns spelare för hemma- och bortalaget, boll, kon, pinne, docka, mål och text. Välj en sak och tryck på planen där den ska stå.", en: "Under Place there are players for the home and away team, ball, cone, pole, mannequin, goal and text. Choose one and tap the pitch where it should go." },
        tip: { sv: "En hel formation lägger du ut under Lag.", en: "A whole formation is put out under Team." },
      },
      {
        title: { sv: "Rita", en: "Draw" },
        text: { sv: "Under Rita finns passning, löpning, dribbling, linje, frihand, yta och zon. Dra med fingret eller musen från start till mål. Verktyget ligger kvar tills du väljer ett annat, så att du kan rita flera i rad.", en: "Under Draw there are pass, run, dribble, line, freehand, area and zone. Drag with your finger or the mouse from start to end. The tool stays in hand until you choose another, so you can draw several in a row." },
        steps: [
          { sv: "Dra i en linjes mittpunkt för att böja den. Dubbelklicka på mittpunkten för att göra den rak igen.", en: "Drag the middle point of a line to bend it. Double-click the middle point to make it straight again." },
          { sv: "En passning kan gå på marken eller i luften. I luften ritas den som en båge med en skugga under; välj under Egenskaper.", en: "A pass can go along the ground or in the air. In the air it is drawn as an arc with a shadow beneath; choose under Properties." },
          { sv: "Börjar du dra en pil på en spelare fäster den där och följer med när spelaren flyttas. Dra pilens startpunkt till en spelare för att fästa den, eller bort för att släppa den.", en: "Start dragging an arrow on a player and it sticks there, following the player when they move. Drag the arrow's start onto a player to stick it, or away to let go." },
        ],
      },
      {
        title: { sv: "Mät", en: "Measure" },
        text: { sv: "Linjalen mäter avståndet mellan två punkter på planen. Med Mått påslaget visas längden på linjer och storleken på ytor.", en: "The ruler measures the distance between two points on the pitch. With Measurements on, lines show their length and areas their size." },
      },
      {
        title: { sv: "Linjer och ytor mellan spelare", en: "Lines and areas between players" },
        steps: [
          { sv: "Markera två eller fler spelare (se guiden Markera och ändra).", en: "Select two or more players (see the guide Selecting and changing)." },
          { sv: "Välj Öppen linje eller Sluten yta under Egenskaper. Linjen följer spelarna när de flyttas.", en: "Choose Open line or Closed area under Properties. The line follows the players when they move." },
        ],
      },
    ],
  },
  {
    slug: "markera",
    title: { sv: "Markera och ändra", en: "Selecting and changing" },
    summary: { sv: "Flytta, ändra utseende, låsa, gruppera och ta bort.", en: "Move, change the look, lock, group and remove." },
    sections: [
      {
        title: { sv: "Markera", en: "Select" },
        steps: [
          { sv: "Tryck på ett objekt med Markera valt. Dess egenskaper visas under Egenskaper.", en: "Tap an object with Select chosen. Its properties show under Properties." },
          { sv: "Dra över gräset för att markera allt inom rutan.", en: "Drag over the grass to select everything inside the box." },
          { sv: "Shift + klick lägger till eller tar bort. På telefon trycker du på Välj flera, som visas uppe till vänster på planen när något är markerat, och sedan på objekten i tur och ordning.", en: "Shift + click adds or takes out. On a phone, tap Pick several, shown at the top left of the pitch once something is selected, and then the objects in turn." },
        ],
      },
      {
        title: { sv: "Ändra", en: "Change" },
        text: { sv: "Under Egenskaper ändrar du färg, storlek, text, nummer och namn, pilspets och tjocklek, fyllning och mönster, beroende på vad du har markerat. Markerar du flera ändrar du dem samtidigt.", en: "Under Properties you change colour, size, text, number and name, arrowhead and thickness, fill and pattern, depending on what you have selected. Select several to change them together." },
        steps: [
          { sv: "Lås ett objekt så att det inte flyttas av misstag.", en: "Lock an object so it isn't moved by mistake." },
          { sv: "Gruppera med Ctrl + G och dela upp med Ctrl + Shift + G. Ctrl + D kopierar.", en: "Group with Ctrl + G and ungroup with Ctrl + Shift + G. Ctrl + D copies." },
          { sv: "Med Gäller alla frames påslaget gäller ändringen objektet i alla frames.", en: "With Applies to all frames on, the change applies to the object in every frame." },
        ],
      },
      {
        title: { sv: "Ta bort", en: "Remove" },
        steps: [
          { sv: "Dra objektet till papperskorgen som visas när du drar, eller tryck på Delete.", en: "Drag the object to the bin that shows while dragging, or press Delete." },
          { sv: "Håll ner Shift (eller ha Gäller alla frames påslaget) för att ta bort det ur alla frames.", en: "Hold Shift (or have Applies to all frames on) to remove it from every frame." },
        ],
        tip: { sv: "Alla kortkommandon visas om du trycker ? på tavlan.", en: "Press ? on the board to see every keyboard shortcut." },
      },
    ],
  },
  {
    slug: "mobil",
    title: { sv: "På telefon och surfplatta", en: "On a phone or tablet" },
    summary: { sv: "Så får planen mest plats på en liten skärm.", en: "How the pitch gets the most room on a small screen." },
    sections: [
      {
        title: { sv: "Verktygen", en: "The tools" },
        text: { sv: "På telefon ligger verktygen på planen: Markera, Placera, Rita och Mät. Den sista knappen flyttar dem mellan en kolumn till höger och en rad längs nederkanten; välj det som lämnar planen fri.", en: "On a phone the tools sit on the pitch: Select, Place, Draw and Measure. The last button moves them between a column on the right and a row along the foot; pick whichever leaves the pitch free." },
        tip: { sv: "Zooma med två fingrar.", en: "Zoom with two fingers." },
      },
      {
        title: { sv: "Panelerna", en: "The panels" },
        text: { sv: "Flikarna längst ner öppnar panelerna ovanpå planen. Är något markerat flyttas planen så att det syns ovanför panelen. Tryck på gräset för att stänga panelen.", en: "The tabs at the bottom open the panels over the pitch. If something is selected, the pitch moves so it shows above the panel. Tap the grass to close the panel." },
      },
      {
        title: { sv: "Frames och uppspelning", en: "Frames and playback" },
        text: { sv: "Under planen finns uppspelning, framesen och + för en ny frame. Tid, rörelse, 3D, slinga och hastighet finns under ⋯. Under fliken Frames bläddrar du mellan frames med ett svep i sidled.", en: "Below the pitch are playback, the frames and + for a new frame. Time, motion, 3D, loop and speed are under ⋯. Under the Frames tab you move between frames with a sideways swipe." },
      },
      {
        title: { sv: "Surfplatta", en: "Tablet" },
        text: { sv: "På surfplatta och dator ligger tavlans knappar i samma rad som sidhuvudet. På en smal skärm finns visa i helskärm, versioner, inställningar och livelektion under ⋯.", en: "On a tablet and computer the board's buttons sit on the header's row. On a narrow screen, full screen, versions, settings and live session are under ⋯." },
      },
    ],
  },
];
