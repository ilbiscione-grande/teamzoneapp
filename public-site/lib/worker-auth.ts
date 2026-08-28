import { timingSafeEqual } from "node:crypto";

export function validWorkerBearer(header: string | null, expected: string): boolean {
  if (!header?.startsWith("Bearer ") || expected.length < 32) return false;
  const supplied = Buffer.from(header.slice(7), "utf8");
  const wanted = Buffer.from(expected, "utf8");
  return supplied.length === wanted.length && timingSafeEqual(supplied, wanted);
}
