import { serverConfig } from "../../../../lib/config";
import { createServerSupabase } from "../../../../lib/supabase-admin";

export async function GET(_request:Request,context:{params:Promise<{token:string}>}){
 try{
  const {token}=await context.params;
  if(!/^[a-f0-9]{32}$/.test(token))return new Response("Not found",{status:404});
  const client=createServerSupabase(serverConfig());
  const {data:resolved,error}=await client.schema("api").rpc("resolve_public_media",{public_token:token});
  if(error||!resolved||resolved.not_found)return new Response("Not found",{status:404});
  const {data:file,error:downloadError}=await client.storage.from(resolved.bucket_id).download(resolved.object_key);
  if(downloadError||!file)return new Response("Not found",{status:404});
  return new Response(file,{headers:{"content-type":"image/webp","cache-control":"public, max-age=60, s-maxage=31536000, immutable","x-content-type-options":"nosniff"}});
 }catch{return new Response("Unavailable",{status:503,headers:{"cache-control":"no-store"}});}
}
