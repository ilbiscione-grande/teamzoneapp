import assert from 'node:assert/strict';
// Run: node supabase/tests/pub07_personal_home.local.mjs --direct-result --written-reports
export async function testWrittenReports(db,read) {
 await db.exec(`create function internal.actor_can_read_event(uuid) returns boolean language sql stable as $$select auth.uid()='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid$$;
 create function internal.get_my_contexts_for_actor() returns table(team_id uuid,team_name text,club_id uuid,club_name text)
 language sql stable as $$select id,name,club_id,'Testklubb'::text from core.teams where auth.uid()='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid$$;`);
 await db.exec(read('supabase/migrations/20260926062708_pub09_personal_dashboard_content.sql'));
 await db.exec(read('supabase/migrations/20260926150243_match_written_reports.sql'));
 const event='30000000-0000-4000-8000-000000000001',team='20000000-0000-4000-8000-000000000001';
 const command='70000000-0000-4000-8000-000000000001';
 const text='Bra kämpat!\n<script>alert("x")</script>';
 const save=(revision,body,publish,id=null)=>db.query('select api.save_match_report(coalesce($1::uuid,gen_random_uuid()),$2,$3,$4,$5) report',[id,event,revision,body,publish]);
 const reject=async(fn,code)=>{await db.exec('savepoint report_rejected');try{await assert.rejects(fn,e=>e.code===code);}finally{await db.exec('rollback to report_rejected');}};
 const projection=async()=> (await db.query('select report_text from public_api.match_result_projections')).rows[0]?.report_text ?? null;
 const privateRead=()=>db.query('select api.get_match_report($1) report',[event]);
 await db.exec("select set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',true)");
 await reject(privateRead,'42501');await reject(()=>save(0,text,true),'42501');
 await db.exec("select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true)");
 await reject(()=>save(0,'x'.repeat(10001),false),'22023');
 await reject(()=>save(0,'  ',true),'22023');
 const draft=(await save(0,text,false,command)).rows[0].report;
 assert.equal(draft.body,text);assert.equal(draft.published,false);
 assert.deepEqual((await save(0,text,false,command)).rows[0].report,draft,'idempotent retry');
 await reject(()=>save(0,text+'changed',false,command),'23505');
 await db.query('select api.set_team_event_visibility($1,true,false,0)',[team]);
 assert.equal(await projection(),null,'draft not projected even with results enabled');
 await save(1,text,true);
 assert.equal(await projection(),text);
 let teamPage=(await db.query('select api.public_list_team_results($1,$2) page',[team,'a'.repeat(64)])).rows[0].page;
 assert.equal(teamPage.items[0].report_text,text,'anonymous website path receives published plain text');
 const dashboard=(await db.query('select api.get_personal_dashboard_content() page')).rows[0].page;
 assert.equal(dashboard.results[0].report_text,text);
 await reject(()=>save(1,'stale',true),'40001');
 // Score correction reprojects and retains the deliberately published report.
 await db.exec('update core.match_projections set score_us=4,revision=revision+1');
 assert.equal(await projection(),text);
 await save(2,'Nytt internt utkast',false);
 assert.equal(await projection(),null,'unpublishing withdraws report');
 teamPage=(await db.query('select api.public_list_team_results($1,$2) page',[team,'a'.repeat(64)])).rows[0].page;
 assert.equal(teamPage.items[0].report_text,null);
 await save(3,text,true);
 await db.query('select api.set_team_event_visibility($1,false,false,1)',[team]);
 assert.equal(await projection(),null,'team results off hides report');
 await db.query('select api.set_team_event_visibility($1,true,false,2)',[team]);
 assert.equal(await projection(),text);
 await db.exec("update public_api.team_projections set visibility='listed'");
 teamPage=(await db.query('select api.public_list_team_results($1,$2) page',[team,'a'.repeat(64)])).rows[0].page;
 assert.equal(teamPage.items.length,0,'private parent hides report');
 await db.exec("update public_api.team_projections set visibility='published';update core.match_workspaces set state='live'");
 assert.equal(await projection(),null,'reopening removes public report with score');
 await reject(()=>save(4,'För tidigt',false),'23514');
 await db.exec("update core.match_workspaces set state='completed';update core.events set archived_at=now()");
 await reject(()=>save(4,'Arkiverad',false),'42501');
 assert.equal((await db.query("select has_table_privilege('authenticated','core.match_reports','select') allowed")).rows[0].allowed,false);
 assert.equal((await db.query("select has_function_privilege('anon','api.get_match_report(uuid)','execute') allowed")).rows[0].allowed,false);
 await db.exec("update core.events set archived_at=null;update internal.publication_runtime_state set enabled=false");
 teamPage=(await db.query('select api.public_list_team_results($1,$2) page',[team,'a'.repeat(64)])).rows[0].page;
 assert.equal(teamPage.available,false,'runtime off suppresses public report');
 await db.exec(`insert into core.profiles values('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
  create or replace function internal.actor_can_manage_event(uuid) returns boolean language sql stable as
   $$select auth.uid() in('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,'cccccccc-cccc-4ccc-8ccc-cccccccccccc'::uuid)$$;
  create or replace function internal.actor_can_read_event(uuid) returns boolean language sql stable as
   $$select internal.actor_can_manage_event($1)$$;
  select set_config('request.jwt.claim.sub','cccccccc-cccc-4ccc-8ccc-cccccccccccc',true);`);
 assert.equal((await privateRead()).rows[0].report.can_publish,false);
 await reject(()=>save(4,'Obehörig publicering',true),'42501');
 await reject(()=>save(4,'Obehörig ändring av publicerad rapport',false),'42501');
 await db.exec("select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true)");
 await save(4,'Utkast',false);
 await db.exec("select set_config('request.jwt.claim.sub','cccccccc-cccc-4ccc-8ccc-cccccccccccc',true)");
 await reject(()=>save(5,'Obehörig publicering',true),'42501');
 await save(5,'Ledaren kan skriva ett utkast',false);
 console.log('PASS: report drafts, publishing/withdrawal, retry, history, bounds, read authorization, results visibility, privacy and dashboard/team read paths');
 if(process.argv.includes('--team-notifications')) {
  const {testTeamNotifications} = await import('./team_notifications.local.mjs');
  await testTeamNotifications(db,read);
 }
}
