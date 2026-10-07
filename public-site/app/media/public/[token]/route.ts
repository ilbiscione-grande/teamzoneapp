import { serverConfig } from "../../../../lib/config";
import { createServerSupabase } from "../../../../lib/supabase-admin";

const badgeTypes = new Set(["image/png", "image/jpeg", "image/webp"]);

export async function GET(_request:Request,context:{params:Promise<{token:string}>}){
 try{
  const {token}=await context.params;
  if(!/^[a-f0-9]{32}$/.test(token))return new Response("Not found",{status:404});
  const client=createServerSupabase(serverConfig());
  const {data:resolved,error}=await client.schema("api").rpc("resolve_public_media",{public_token:token});
  if(!error&&resolved&&!resolved.not_found){
   const {data:file,error:downloadError}=await client.storage.from(resolved.bucket_id).download(resolved.object_key);
   if(downloadError||!file)return new Response("Not found",{status:404});
   // Not immutable: a removed or replaced image (a wrong photo of a child)
   // must stop being served within an hour, not linger in a shared cache.
   return new Response(file,{headers:{"content-type":"image/webp","cache-control":"public, max-age=300, s-maxage=3600","x-content-type-options":"nosniff","content-security-policy":"default-src 'none'; sandbox"}});
  }
  // A published club's badge. Its address changes when the badge is replaced;
  // a short shared cache lets removal and unpublishing take effect.
  const {data:badge,error:badgeError}=await client.schema("api").rpc("resolve_public_club_badge",{public_token:token});
  if(badgeError||!badge||badge.not_found||badge.bucket_id!=="club-badges"||!badgeTypes.has(badge.mime_type))return new Response("Not found",{status:404});
  const {data:file,error:downloadError}=await client.storage.from(badge.bucket_id).download(badge.object_key);
  if(downloadError||!file)return new Response("Not found",{status:404});
  return new Response(file,{headers:{"content-type":badge.mime_type,"cache-control":"public, max-age=300, s-maxage=3600","x-content-type-options":"nosniff","content-security-policy":"default-src 'none'; sandbox"}});
 }catch{return new Response("Unavailable",{status:503,headers:{"cache-control":"no-store"}});}
}
