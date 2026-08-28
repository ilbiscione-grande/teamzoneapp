# Beslut och frågor från målbilden

## Beslut som målbilden i praktiken föreslår

Följande kan behandlas som starka produktförslag, men ska fortfarande signeras:

| Förslag | Påverkar |
|---|---|
| Fem gemensamma huvudytor med rollanpassat innehåll | PD-01/02/18 |
| Flera samtidiga roller/capabilities för samma person | PD-01/03 |
| Platshållare är rosteridentiteter, inte falska Auth-konton | PD-03 |
| Ett hemlag plus flera spelbara lag | PD-07 |
| Grundappen fungerar utan betalda integrationsdata | PD-04/15 |
| Match v2 behålls som matchens serverkontrakt | PD-09, REQ-MATCH-01 |
| Publik data styrs av klubb-/laginställningar | PD-16/20 |

## Arkitekturstyrande frågor att avgöra först

1. **Rollmodell:** Är “klubbfunktionär” en huvudroll eller en uppsättning klubbcapabilities som kassör, ordförande och administratör?
2. **Kontext:** Ska användaren välja ett aktivt lag/klubb för hela appen, eller ska Hem/Kalender/Inbox alltid kunna aggregera flera contexts?
3. **Personmodell:** Får samma människa ha flera rosteridentiteter mellan klubbar, eller finns en global person med tenantseparerade representationer?
4. **Meddelanden:** Ska spelare initialt bara kunna skriva till guardians, ledare och lagchatten? Vem får slå på player-to-player och för vilka åldrar?
5. **Publik trupp:** Ska minderåriga vara dolda som default och kräva separat samtycke för namn/bild/statistik?
6. **Eventägande:** Vem äger och får redigera ett event som delas av flera lag?
7. **Squad/callup:** Ska grupper alltid skapa ett planutkast, så att ingen separat direktväg till callups finns?
8. **Närvaro:** Är “ingen status satt” samma sak som deltog inte? Rekommendation: nej, använd `unknown` och explicit `absent`.
9. **Assistant Coach:** Är första versionen regelbaserad sammanställning med säkra actions, eller får en generativ modell läsa person-/hälsodata?
10. **Gratisgräns:** Vilka räknas i 25 användare – aktiva Auth-konton, rosterpersoner, guardians och klubbfunktionärer?

## Nya beslut som inte täcks fullt av PD-01–PD-20

| ID | Beslut | Föreslagen ägare | Rekommendation |
|---|---|---|---|
| ND-01 | Assistant Coach dataåtkomst, modellleverantör, prompt-/outputretention och action confirmation | Product + privacy/security | Börja regelbaserat/read-only; mutation kräver explicit preview/confirm och vanlig serverauthorization. |
| ND-02 | Assistant Coach för minderåriga och hälso-/utvecklingsdata | Privacy/legal + product | Ingen generativ behandling innan DPIA/samtycke/ålderspolicy är beslutad. |
| ND-03 | Integrationskontrakt mellan appmoduler och web tools | Tech lead + product | Stabil versionerad API/eventmodell; ingen delad direktdatabas mellan produkter. |
| ND-04 | Fristående webtool-identitet och senare club linking | Tech lead + security | Separat tenant och explicit link/consent; undvik oscopead profilmatchning. |
| ND-05 | Bokning som grundapp, workspace eller web tool | Product + club operations | Lägg beslut efter kärnflöden; eventintegration ska vara API-baserad oavsett paketering. |
| ND-06 | SMS-fallback, samtycke, kostnadsansvar och deliveryprovider | Product + privacy + billing | Senare fas; opt-in, rate limit och leveranslogg krävs. |
| ND-07 | Produktanalys och telemetry | Product + privacy | Privacy-by-default, pseudonymisering och separat consent/retention från sportsdata. |
| ND-08 | Video/media storage, rättigheter och retention | Product + privacy/legal + operations | Kräver separat mediepolicy innan Video Analyzer specificeras. |
| ND-09 | Självskattning 1–5 efter träning och vem som får se den | Product + privacy + coach | Behandla som känslig utvecklingsdata; visibility och retention måste beslutas. |
| ND-10 | Prispunkter, kvotmått, årsplan och modulrabatt | Product + billing/finance | Validera kommersiellt; implementera inte hårdkodade priser från målbildsdokumentet. |

## Rekommenderade standardval

- Capabilitybaserad authorization, medan UI kan visa begripliga huvudroller.
- Personcentrerad Hem/Kalender/Inbox med filter; skrivoperationer kräver explicit target context.
- `unknown`, `present`, `late`, `partial`, `absent` som närvarotillstånd.
- Publik synlighet och player-to-player messaging ska vara avstängda som default för minderåriga.
- Assistant Coach ska först vara en transparent signal-/actionmotor ovanpå verifierade queries, inte en autonom agent.

