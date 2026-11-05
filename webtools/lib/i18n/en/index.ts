// English for each Swedish text, one file per area.

import { account } from "./account.ts";
import { billing } from "./billing.ts";
import { editorMore } from "./editor-more.ts";
import { editorPanels } from "./editor-panels.ts";
import { editorTools } from "./editor-tools.ts";
import { library } from "./library.ts";
import { sharing } from "./sharing.ts";
import { shell } from "./shell.ts";

export const english: Record<string, string> = { ...shell, ...account, ...billing, ...editorPanels, ...editorTools, ...editorMore, ...library, ...sharing };
