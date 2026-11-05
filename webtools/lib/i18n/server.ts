import { cookies, headers } from "next/headers";
import { localeCookie, pickLocale, type Locale } from "./locale.ts";
import { translator, type Translate } from "./translate.ts";

export const englishOpen = () => process.env.TACTICSBOARD_ENGLISH === "on";

export async function serverLocale(): Promise<Locale> {
  const [cookieStore, headerList] = await Promise.all([cookies(), headers()]);
  return pickLocale(cookieStore.get(localeCookie)?.value, headerList.get("accept-language"), englishOpen());
}

export async function serverT(): Promise<Translate> {
  return translator(await serverLocale());
}

/**
 * For a link's title and picture in a chat. The service fetching them states
 * no language, and the link's receiver is most often Swedish so far.
 */
export async function previewT(): Promise<Translate> {
  const headerList = await headers();
  return headerList.get("accept-language") ? serverT() : translator("sv");
}
