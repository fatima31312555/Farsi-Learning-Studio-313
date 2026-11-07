(function () {
  var C = window.DARS_CONFIG;
  window.$ = function (id) { return document.getElementById(id); };
  window.esc = function (s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  };
  window.configured = !/YOUR-/.test(C.SUPABASE_URL + C.SUPABASE_ANON_KEY);
  window.sb = window.configured ? window.supabase.createClient(C.SUPABASE_URL, C.SUPABASE_ANON_KEY) : null;

  var tt;
  window.toast = function (m) {
    var t = $("toast"); if (!t) return;
    t.textContent = m; t.classList.add("show");
    clearTimeout(tt); tt = setTimeout(function () { t.classList.remove("show"); }, 2000);
  };

  window.say = function (x) {
    if (!("speechSynthesis" in window)) { toast("Speech is not supported here"); return; }
    var u = new SpeechSynthesisUtterance(x); u.lang = "fa-IR"; u.rate = 0.8;
    var v = speechSynthesis.getVoices().filter(function (a) { return /^fa/i.test(a.lang); });
    if (v.length) u.voice = v[0];
    speechSynthesis.cancel(); speechSynthesis.speak(u);
  };

  window.shuf = function (a) {
    a = a.slice();
    for (var i = a.length - 1; i > 0; i--) { var j = Math.floor(Math.random() * (i + 1)); var t = a[i]; a[i] = a[j]; a[j] = t; }
    return a;
  };

  window.showSetupNotice = function () {
    document.body.insertAdjacentHTML("afterbegin",
      '<div class="msg" style="margin:0;border-radius:0;text-align:center">Setup needed: open <b>js/config.js</b> and paste your Supabase URL and anon key (see README).</div>');
  };

  // returns {session, profile} or redirects to login
  window.requireUser = async function () {
    if (!configured) { showSetupNotice(); return null; }
    var r = await sb.auth.getSession();
    if (!r.data.session) { location.href = "login.html"; return null; }
    var p = await sb.from("profiles").select("*").eq("id", r.data.session.user.id).single();
    if (p.error) { alert("Could not load your profile: " + p.error.message); return null; }
    return { session: r.data.session, profile: p.data };
  };

  window.signOut = async function () { await sb.auth.signOut(); location.href = "index.html"; };
})();
