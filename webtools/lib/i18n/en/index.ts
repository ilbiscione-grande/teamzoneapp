// English for each Swedish text, one file per area.

import { account } from "./account.ts";
import { billing } from "./billing.ts";
import { shell } from "./shell.ts";

export const english: Record<string, string> = { ...shell, ...account, ...billing };
