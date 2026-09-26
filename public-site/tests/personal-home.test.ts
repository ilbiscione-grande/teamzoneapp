import assert from "node:assert/strict";
import test from "node:test";
import { channelHref, feedHref, mergeFeed, safeReturnPath, type FeedItem } from "../lib/personal-home.ts";

test("account return paths cannot leave this site or inject URL control characters", () => {
  assert.equal(safeReturnPath("/thomas-klubb/thomas-lag"), "/thomas-klubb/thomas-lag");
  for (const value of [null, "//attacker.example", "https://attacker.example", "/\\attacker", "/%2f%2fattacker", "/club?next=https://attacker", "/club\n"]) assert.equal(safeReturnPath(value), null);
});
test("following links distinguish a club from a team under the club", () => {
  assert.equal(channelHref({kind:"club",id:"c",name:"C",slug:"club"}), "/club");
  assert.equal(channelHref({kind:"team",id:"t",name:"T",slug:"team",club_slug:"club"}), "/club/team");
});
test("feed pagination merges repeated articles and preserves different item types", () => {
  const news: FeedItem = {id:"id",kind:"news",happened_at:"2026-09-25",title:"Old",club_name:"Club",club_slug:"club",article_slug:"news"};
  const result: FeedItem = {...news,kind:"result",team_slug:"team",score_us:0,score_opponent:0};
  const merged=mergeFeed([news],[{...news,title:"Updated"},result]);
  assert.equal(merged.length,2);
  assert.equal(merged[0].title,"Updated");
  assert.equal(feedHref(merged[0]),"/club/nyheter/news");
  assert.equal(feedHref(merged[1]),"/club/team#resultat");
  assert.equal(merged[1].score_us,0);
});
