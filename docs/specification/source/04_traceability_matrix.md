# Spårbarhet från målbild till audit och krav

| Målområde | Delta | Auditbeslut | Befintliga krav | Nytt beslut/kravbehov |
|---|---|---|---|---|
| Fem huvudytor | CHG-NAV-01 | PD-01/02/18 | REQ-ID-02, REQ-CLI-04 | IA- och roll-content-matris |
| Assistant Coach | CHG-AI-01 | PD-12/13 | REQ-SIG-01, REQ-SEC-01, REQ-CLI-01 | ND-01/02; AI safety/evaluation |
| Multi-context kalender | CHG-CAL-01 | PD-01/05 | REQ-ID-02, REQ-EVT-02, REQ-CAL-01 | Aggregation/read kontra explicit write target |
| Inboxrestriktioner | CHG-MSG-01 | PD-10/11 | REQ-MSG-01–03 | Ålders-/club-config för player messaging |
| Platshållare/claim | CHG-ID-02 | PD-03 | REQ-MEM-01/02 | Claim-proof och mergekontrakt |
| Hemlag/spelbara lag | CHG-ROSTER-01 | PD-07 | REQ-SEC-02, REQ-SQUAD-02 | Representationbaserad statistik |
| Lån/övergång | CHG-ROSTER-02 | PD-03/07 | REQ-MEM-01/02 | Temporal roster/transfermodell |
| EventDetails | CHG-EVT-01 | PD-05/06 | REQ-EVT-01/02, REQ-CALL-01 | Eventtypfält och visibilityschema |
| Kallelse/push/SMS | CHG-CALL/PUSH/SMS | PD-08/11 | REQ-SEC-05, REQ-CALL-01/02 | ND-06 |
| Match Space | CHG-MATCH-01 | PD-09 | REQ-MATCH-01 | Bevara liveverifierat v2-kontrakt |
| Training/Season/Development | CHG-TRAIN/SEASON/TEAMDEV/PLAYERDEV | PD-12/13 | REQ-SIG-01 | ND-09 och tydlig modulgräns |
| Economy/Board Room | CHG-ECO-01 | PD-14/15 | REQ-ECO-01, REQ-BILL-01/02 | Capabilityseparation |
| Publik klubb-/lagsajt | CHG-PUBLIC-01 | PD-16/17/20 | REQ-WEB-01–03 | Consent/publication state machine |
| Web tools | CHG-WEBTOOL-01–04 | PD-04/15/17 | REQ-SEC-01/04, REQ-BILL-02 | ND-03–05/08; bokning fastställd som web tool i WID-09 |
| Pricing/quota | CHG-BILL-01/02 | PD-04/15 | REQ-BILL-01/02 | ND-10 |
| Usage analytics | CHG-ANALYTICS-01 | PD-11/16 | REQ-CLI-01, REQ-OPS-01 | ND-07 |

## Spårbarhetsregel

Varje framtida story ska länka minst ett CHG-ID och ett REQ-ID. Om storyn beror på ett öppet PD-/ND-beslut får den inte gå till implementation innan beslutet är dokumenterat.
