'use strict';
const q = s => document.querySelector(s);
const client = window.supabase.createClient(window.DRIVEMATE_CONFIG.url, window.DRIVEMATE_CONFIG.publishableKey);
let user, profile, context = {}, signup = false, emailForCode = '', activeView = location.hash === '#driver' ? 'driver' : 'owner', generation = 0;
function message(text = '', error = false) { q('#message').textContent = text; q('#message').classList.toggle('error', error); }
function checked(result) { if (result.error) throw result.error; return result.data; }
async function task(button, action) { button.disabled = true; message(); try { await action(); } catch (e) { message(e.message || 'Something went wrong. Please try again.', true); } finally { button.disabled = false; } }
function node(tag, text, className) { const el = document.createElement(tag); if (text !== undefined) el.textContent = text; if (className) el.className = className; return el; }
function action(text, fn, className = 'outline') { const b = node('button', text, className); b.type = 'button'; b.onclick = () => task(b, fn); return b; }
function heading(title, text) { const w = node('section'); w.append(node('h2', title)); if (text) w.append(node('p', text, 'notice')); q('#workspace').replaceChildren(w); return w; }
function setMode(value) { signup = value; q('#signup-tab').classList.toggle('active', value); q('#login-tab').classList.toggle('active', !value); q('#name-field').hidden = !value; q('[name=name]').required = value; q('#auth-title').textContent = value ? 'Make yourself at home' : 'Welcome back'; q('#auth-submit').textContent = value ? 'Email me a sign-up link →' : 'Email me a sign-in link →'; q('#otp-form').hidden = true; q('#auth-form').hidden = false; message(); }
q('#login-tab').onclick = () => setMode(false);
q('#signup-tab').onclick = () => setMode(true);
q('#auth-form').onsubmit = e => { e.preventDefault(); const f = e.currentTarget; task(q('#auth-submit'), async () => { emailForCode = f.elements.email.value.trim(); checked(await client.auth.signInWithOtp({ email: emailForCode, options: { shouldCreateUser: signup, emailRedirectTo: new URL('/account.html', location.origin).href, data: signup ? { full_name: f.elements.name.value.trim() } : undefined } })); f.hidden = true; q('#otp-form').hidden = false; message('Check your email for a secure sign-in link. If the message includes a code, you can enter it below. Delivery may take a minute.'); }); };
q('#otp-form').onsubmit = e => { e.preventDefault(); task(e.currentTarget.querySelector('button'), async () => { checked(await client.auth.verifyOtp({ email: emailForCode, token: e.currentTarget.elements.token.value.trim(), type: 'email' })); }); };
q('#change-email').onclick = () => setMode(signup);
q('#signout').onclick = () => task(q('#signout'), async () => { checked(await client.auth.signOut({ scope: 'local' })); });
async function sessionChanged(session) {
 const run = ++generation; user = session?.user; profile = null; context = {};
 q('#auth-panel').hidden = !!user; q('#dashboard').hidden = !user; q('#signout').hidden = !user; q('#admin-tab').hidden = true; q('#workspace').replaceChildren();
 if (!user) { q('#auth-form').hidden = false; q('#otp-form').hidden = true; return; }
 try {
  const results = await Promise.all([client.from('profiles').select('*').eq('user_id', user.id).maybeSingle(), client.rpc('account_context')]);
  if (run !== generation) return;
  profile = checked(results[0]); context = checked(results[1]) || {};
  q('#greeting').textContent = profile?.full_name || 'Complete your profile'; q('#account-email').textContent = user.email;
  q('#account-badge').textContent = context.is_admin ? 'Administrator' : profile?.account_kind === 'driver' ? 'Driver account' : 'Owner account'; q('#admin-tab').hidden = !context.is_admin;
  if (!profile) profileForm(); else await showView(activeView);
 } catch(e) { message(e.message, true); }
}
function profileForm() {
 const w = heading('A little about you', 'Your profile stays with your account. You can apply to drive later.'); const f = node('form');
 f.innerHTML = '<label>Full name<input name="full_name" autocomplete="name" maxlength="100" required></label><label>I’m here to<select name="kind"><option value="owner">Find a driver for my car</option><option value="driver">Apply to drive</option></select></label><button class="primary" type="submit">Save profile →</button>';
 f.elements.full_name.value = user.user_metadata?.full_name || '';
 f.onsubmit = e => { e.preventDefault(); task(f.querySelector('button'), async () => { checked(await client.rpc('save_account', { p_name: f.elements.full_name.value.trim(), p_kind: f.elements.kind.value })); activeView = f.elements.kind.value; await sessionChanged({ user }); }); }; w.append(f);
}
async function showView(view) {
 activeView = view; document.querySelectorAll('.account-menu button').forEach(b => b.classList.toggle('active', b.id === view + '-tab'));
 if (!profile) return profileForm();
 if (view === 'admin') { if (!context.is_admin) throw new Error('Administrator access required.'); return adminView(); }
 if (view === 'driver') return driverView();
 const w = heading('Your journeys', 'Your account is ready. Live booking requests will open after our Bengaluru pilot checks are complete.');
 const bookings = checked(await client.from('bookings').select('id,pickup_address,starts_at,status').eq('owner_id',user.id).order('starts_at',{ascending:false}).limit(30));
 if (!bookings.length) w.append(node('p','No live bookings yet. The booking page still offers a separate demo.','empty-state'));
 for (const b of bookings) { const card = node('article', undefined, 'review-card'); card.append(node('h3',b.pickup_address),node('p',new Intl.DateTimeFormat('en-IN',{ dateStyle:'medium',timeStyle:'short',timeZone:'Asia/Kolkata' }).format(new Date(b.starts_at))+' IST · '+b.status,'notice')); w.append(card); }
 w.append(action('Explore booking preview',async()=>{location.href='/';}));
}
q('#owner-tab').onclick = () => task(q('#owner-tab'),()=>showView('owner'));
q('#driver-tab').onclick = () => task(q('#driver-tab'),()=>showView('driver'));
q('#admin-tab').onclick = () => task(q('#admin-tab'),()=>showView('admin'));
async function driverView() {
 const w = heading('Drive with DriveMate', 'Apply for scheduled driving opportunities in Bengaluru. Submitting an application does not activate your driver account.');
 const app = checked(await client.from('driver_applications').select('*').eq('user_id',user.id).maybeSingle());
 if (!app) {
  const f = node('form'); f.innerHTML='<label>Years of driving experience<input name="experience" type="number" min="0" max="70" step="1" required></label><label>Cars you can drive<select name="transmission"><option value="both">Manual and automatic</option><option value="manual">Manual only</option><option value="automatic">Automatic only</option></select></label><label>Service city<input value="Bengaluru, Karnataka" readonly></label><label class="check-label"><input name="consent" type="checkbox" required><span>I agree that DriveMate may store my application and verification evidence for an authorised reviewer to assess my driving eligibility. I understand this pilot currently accepts sample documents only.</span></label><button class="primary" type="submit">Submit pilot application →</button>';
  f.onsubmit=e=>{e.preventDefault();task(f.querySelector('button'),async()=>{checked(await client.rpc('submit_driver_application',{p_experience:Number(f.elements.experience.value),p_transmission:f.elements.transmission.value,p_consent:f.elements.consent.checked}));await driverView();message('Application saved. Add sample documents to test the review workflow.');});}; w.append(f); return;
 }
 const status = checked(await client.from('driver_verifications').select('status,licence_expires_on').eq('driver_id',user.id).single());
 w.append(node('span',status.status.replaceAll('_',' '),'pill'),node('p',context.phone_verified ? 'Phone verified.' : 'Phone verification is required before a driver can be approved. Phone OTP is not configured for this pilot yet.','notice'));
 if (status.status !== 'pending') { w.append(node('p','Your application has been reviewed. Contact the pilot team if you need to correct or resubmit evidence.','notice')); return; }
 const docs = checked(await client.from('driver_documents').select('kind,object_path').eq('driver_id',user.id));
 for (const [kind,title] of [['licence','Driving licence sample'],['identity','Identity document sample'],['portrait','Profile photo sample']]) {
  const row=node('div',undefined,'document-row'); row.append(node('h3',title)); const found=docs.find(d=>d.kind===kind);
  if(found) row.append(node('p','Uploaded securely · awaiting review','notice')); else {
   const f=node('form'); const l=node('label','Choose a sample file (PDF, JPG, or PNG · up to 5 MB)'); const input=document.createElement('input'); input.type='file';input.accept='.pdf,.jpg,.jpeg,.png';input.required=true;l.append(input); const b=node('button','Upload sample','outline');b.type='submit';f.append(l,b);
   f.onsubmit=e=>{e.preventDefault();task(b,async()=>{const file=input.files[0];if(!file||file.size>5242880||!['application/pdf','image/jpeg','image/png'].includes(file.type))throw new Error('Choose a PDF, JPG, or PNG no larger than 5 MB.');const ext={'application/pdf':'pdf','image/jpeg':'jpg','image/png':'png'}[file.type];const path=user.id+'/'+crypto.randomUUID()+'.'+ext;checked(await client.storage.from('driver-verification').upload(path,file,{upsert:false,contentType:file.type}));checked(await client.rpc('register_driver_document',{p_kind:kind,p_path:path}));await driverView();message('Sample document uploaded.');});};row.append(f);
  } w.append(row);
 }
}
async function adminView() {
 const w=heading('Driver review queue','Review each piece of evidence. Approval also requires a verified phone and a current licence. Only authorised administrators can record a decision.');
 const apps=checked(await client.from('driver_applications').select('user_id,experience_years,transmission,created_at').order('created_at',{ascending:false}).limit(50));
 if(!apps.length){w.append(node('p','No driver applications to review yet.','empty-state'));return;}
 const ids=apps.map(a=>a.user_id);const [ps,vs,ds]=await Promise.all([client.from('profiles').select('user_id,full_name').in('user_id',ids),client.from('driver_verifications').select('*').in('driver_id',ids),client.from('driver_documents').select('*').in('driver_id',ids)]);const profiles=checked(ps),verifications=checked(vs),docs=checked(ds);
 for(const app of apps){const v=verifications.find(x=>x.driver_id===app.user_id);const card=node('article',undefined,'review-card');card.append(node('h3',profiles.find(p=>p.user_id===app.user_id)?.full_name||'Driver applicant'),node('span',v?.status||'pending','pill'),node('p',`${app.experience_years} years of experience · ${app.transmission}`,'notice'));
 const files=node('div',undefined,'files');for(const d of docs.filter(d=>d.driver_id===app.user_id)){files.append(action('View '+d.kind,async()=>{const data=checked(await client.storage.from('driver-verification').createSignedUrl(d.object_path,60));const a=node('a','Open private document (expires in 60 seconds)');a.href=data.signedUrl;a.target='_blank';a.rel='noopener noreferrer';files.append(a);}));}card.append(files);
 const f=node('form');f.innerHTML='<label>Decision<select name="status"><option value="rejected">Reject application</option><option value="suspended">Suspend eligibility</option><option value="approved">Approve after all checks</option></select></label><label>Licence expiry (required for approval)<input name="expiry" type="date"></label><label class="check-label"><input name="identity" type="checkbox"><span>I checked the identity evidence and matched it to the applicant.</span></label><label class="check-label"><input name="licence" type="checkbox"><span>I checked licence validity and the relevant vehicle category.</span></label><label>Private review note<textarea name="note" rows="3" minlength="5" maxlength="2000" required placeholder="Record checks performed and the reason for this decision."></textarea></label><button class="primary" type="submit">Record review decision →</button>';
 f.onsubmit=e=>{e.preventDefault();task(f.querySelector('button'),async()=>{checked(await client.rpc('review_driver_application',{p_driver:app.user_id,p_status:f.elements.status.value,p_expiry:f.elements.expiry.value||null,p_identity_checked:f.elements.identity.checked,p_licence_checked:f.elements.licence.checked,p_note:f.elements.note.value.trim()}));await adminView();message('Review recorded in the audit trail.');});};card.append(f);w.append(card);}
}
client.auth.onAuthStateChange((_event,session)=>{setTimeout(()=>sessionChanged(session),0);});
client.auth.getSession().then(r=>{if(r.error)message(r.error.message,true);else if(!user)sessionChanged(r.data.session);});
setMode(false);
