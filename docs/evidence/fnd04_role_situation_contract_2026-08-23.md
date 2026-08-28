# FND-04 – Roll- och situationsmatris

**Datum:** 2026-08-23  
**Status:** VERIFIERAD  
**Omfattning:** Produkt- och klientkontrakt. Ingen livebackend, provisionering, webtools eller workspace.

## Resultat

- Ett fast produktkontrakt definierar mål, viktig information, primära actions och uttryckligen dold information för `leader`, `player`, `guardian` och `club_functionary`.
- Kontraktet täcker Hem, Laget, Kalender och Inbox.
- Ett separat situationslager prioriterar mobil under aktivitet, tabletbaserad planering och desktop/web-administration utan att någon enhetstyp tilldelar extra behörighet.
- Capabilities och objektscope förblir enda auktoritativa åtkomstmodell. Rollpaket används endast för presentation och prioritering.
- Okända, legacyliknande eller felstavade rollpaket faller stängt och blir aldrig syntetisk player/admin.
- Guardianflöden är uttryckligen barnscopeade.
- Klubbfunktionär får ingen implicit coaching-, hälso-, team-, ekonomi- eller styrelsebehörighet.

## Artefakter

- `docs/implementation/role_and_situation_contract.md` – läsbart produktkontrakt och tabeller.
- `lib/src/core/product/role_situation_contract.dart` – maskinläsbar kontraktsmodell.
- `test/fnd04_role_situation_contract_test.dart` – positiva, negativa, fail-closed- och fullständighetstester.

## Verifiering

- Samtliga 16 roll/huvudyta-kombinationer har mål, information, actions och negativa regler.
- Samtliga 12 roll/situation-kombinationer har prioritet, layoutregel och nedprioriteringar.
- Player och guardian saknar rosteradmin, eventskapande och närvaro utan separat capability.
- Guardian kräver barnväljare/barnscope i Hem, Kalender och Inbox.
- Klubbfunktionär saknar implicit coaching och känslig spelaråtkomst.
- Dokumenttestet fryser fyra huvudytor, fyra roller, tre situationer och capabilityprincipen.
- `flutter analyze`: **No issues found**.
- Riktat FND-04-test: **9/9 passerar**.
- Full regressionssvit: **104/104 passerar**.

## Användning framåt

HOME-, TEAM-, CAL- och MSG-korten ska hänvisa till `docs/implementation/role_and_situation_contract.md`. Varje ny action ska ha minst ett positivt capability/scope-test och ett negativt test som verifierar frånvaro eller disabled-läge. Serverkontrollen kvarstår alltid även när klienten döljer en action.
