import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { correlationId, sanitizedLog, withCorrelation } from "../_shared/observability.ts";

const jsonHeaders={"content-type":"application/json"};
const decode=(value:string)=>Uint8Array.from(atob(value),character=>character.charCodeAt(0));
const isWebp=(bytes:Uint8Array)=>bytes.length>=12&&new TextDecoder().decode(bytes.slice(0,4))==="RIFF"&&new TextDecoder().decode(bytes.slice(8,12))==="WEBP";

Deno.serve(async(request)=>{
 const requestId=correlationId(request);const respond=(response:Response)=>withCorrelation(response,requestId);
 if(request.method!=="POST")return respond(new Response("Method not allowed",{status:405}));
 const url=Deno.env.get("SUPABASE_URL");
 const secretKeys=JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")??"{}");
 const secret=secretKeys.default??Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 const providerUrl=Deno.env.get("PUBLIC_MEDIA_PROVIDER_URL");const providerKey=Deno.env.get("PUBLIC_MEDIA_PROVIDER_KEY");
 if(!url||!secret||!providerUrl||!providerKey||!providerUrl.startsWith("https://")){
  sanitizedLog("worker.unavailable","error",requestId,{component:"public_media",result:"not_configured"});
  return respond(new Response(JSON.stringify({error:"worker_not_configured"}),{status:503,headers:jsonHeaders}));
 }
 const client=createClient(url,secret,{auth:{persistSession:false}});
 const {data:items,error:claimError}=await client.schema("api").rpc("claim_public_media_batch",{batch_size:10});
 if(claimError)return respond(new Response(JSON.stringify({error:"claim_failed"}),{status:500,headers:jsonHeaders}));
 let ready=0,rejected=0,failed=0;
 for(const item of items??[]){
  let scanState="rejected",variantState="failed",variantKey:string|null=null,width:number|null=null,height:number|null=null;
  try{
   const {data:signed,error:signedError}=await client.storage.from(item.source_bucket).createSignedUrl(item.source_object_key,300);
   if(signedError||!signed?.signedUrl)throw new Error("source_unavailable");
   const provider=await fetch(providerUrl,{method:"POST",headers:{authorization:`Bearer ${providerKey}`,"content-type":"application/json"},body:JSON.stringify({source_url:signed.signedUrl,output:{format:"webp",max_width:2048,max_height:2048,strip_metadata:true},scan:{required:true}}),signal:AbortSignal.timeout(30000)});
   if(!provider.ok)throw new Error("provider_failed");
   const result=await provider.json();
   if(result.clean!==true){variantState="removed";rejected++;}
   else{
    const bytes=decode(result.output_base64??"");
    if(!isWebp(bytes)||bytes.length>5242880)throw new Error("invalid_variant");
    variantKey=`${item.club_id}/${item.public_token}.webp`;width=Number(result.width);height=Number(result.height);
    if(!Number.isInteger(width)||!Number.isInteger(height)||width!<1||height!<1||width!>4096||height!>4096)throw new Error("invalid_dimensions");
    const {error:uploadError}=await client.storage.from("public-media-variants").upload(variantKey,bytes,{contentType:"image/webp",upsert:false});
    if(uploadError)throw new Error("variant_upload_failed");
    scanState="clean";variantState="ready";ready++;
   }
  }catch(_){failed++;}
  const {error:finishError}=await client.schema("api").rpc("finish_public_media_processing",{asset_id:item.asset_id,scan_state:scanState,variant_state:variantState,variant_object_key:variantKey,width,height});
  if(!finishError)await client.storage.from(item.source_bucket).remove([item.source_object_key]);
 }
 sanitizedLog("worker.completed","info",requestId,{component:"public_media",result:"completed"});
 return respond(new Response(JSON.stringify({claimed:(items??[]).length,ready,rejected,failed}),{status:200,headers:jsonHeaders}));
});
