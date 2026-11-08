import type { Booking } from "./booking.ts";

export type BookingChangeScope = "booking" | "series_forward" | "series_all" | "event_forward" | "event_all";
export function bookingChangeScopes(booking: Pick<Booking, "series_id" | "resource_event_series">): { value: BookingChangeScope; label: string; hint: string }[] {
  return [
    { value: "booking", label: "Endast detta tillfälle", hint: "Övriga tillfällen behåller sina tider och resursval." },
    ...(booking.series_id ? [
      { value: "series_forward" as const, label: "Detta och följande i bokningsserien", hint: "Utgå från det valda tillfället. Tidigare tillfällen i serien lämnas kvar." },
      { value: "series_all" as const, label: "Alla kommande i bokningsserien", hint: "Även kommande tillfällen före det valda ingår. Passerade tillfällen ändras inte." },
    ] : []),
    ...(booking.resource_event_series ? [
      { value: "event_forward" as const, label: "Detta och följande i aktivitetsserien", hint: "Aktiviteterna och deras resursbokningar följer med." },
      { value: "event_all" as const, label: "Alla kommande i aktivitetsserien", hint: "Även kommande aktiviteter före den valda ingår. Passerade aktiviteter ändras inte." },
    ] : []),
  ];
}

export function bookingConflictHint(reason: string): string {
  if (reason === "resource_busy") return "Välj en annan tid eller ändra resursvalet. En helplan och dess underdelar kan inte bokas samtidigt.";
  if (reason === "resource_outside_disposition") return "Välj en tid inom resursens dispositionsperiod och öppettider. Även överordnade resursers begränsningar gäller.";
  if (reason === "resource_inactive") return "Ta bort den inaktiva resursen från ändringen och välj en bokningsbar resurs.";
  if (reason === "invalid_time") return "Kontrollera start och slut för tillfället. Sluttiden behöver ligga efter starttiden.";
  return "Ändra tid, resursval eller omfattning och förhandsvisa på nytt. Inget sparas innan kontrollen är godkänd.";
}
