/* Linkd landing — Supabase waitlist insert + live hero-card personalization.

   The anon public key is safe to expose: per RLS it can INSERT only, never
   read/update/delete (see the waitlist_signups policy). */

(function () {
  "use strict";

  /* ------------------------------------------------ Supabase waitlist --- */

  var SUPABASE_URL = "https://rtcxdwqdewudrzctwlbo.supabase.co";
  var SUPABASE_ANON_KEY =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ0Y3hkd3FkZXd1ZHJ6Y3R3bGJvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE5MDUyOTIsImV4cCI6MjA5NzQ4MTI5Mn0.WnZD5_RfNGsQd0d6xZ9Mp8Y1P-HQVG6o-HqxZJECni8";
  var ENDPOINT = SUPABASE_URL + "/rest/v1/waitlist_signups";

  var yearEl = document.getElementById("year");
  if (yearEl) yearEl.textContent = String(new Date().getFullYear());

  function setStatus(el, message, kind) {
    el.textContent = message;
    el.classList.remove("is-error", "is-success");
    if (kind) el.classList.add("is-" + kind);
  }

  async function insertSignup(payload) {
    return fetch(ENDPOINT, {
      method: "POST",
      headers: {
        apikey: SUPABASE_ANON_KEY,
        Authorization: "Bearer " + SUPABASE_ANON_KEY,
        "Content-Type": "application/json",
        Prefer: "return=minimal", // insert-only RLS: don't ask for the row back
      },
      body: JSON.stringify(payload),
    });
  }

  function wireForm(form) {
    if (!form) return;
    var statusEl = form.querySelector("[data-status]");
    var button = form.querySelector("button[type=submit]");
    var emailInput = form.querySelector("input[type=email]");
    var roleInput = form.querySelector("select[name=role]");
    var defaultLabel = button.getAttribute("data-default-label") || button.textContent;

    form.addEventListener("submit", async function (e) {
      e.preventDefault();

      var email = (emailInput.value || "").trim();
      if (!emailInput.checkValidity() || !email) {
        setStatus(statusEl, "Please enter a valid email address.", "error");
        emailInput.focus();
        return;
      }

      var payload = { email: email.toLowerCase() };
      if (roleInput && roleInput.value) payload.role_or_use_case = roleInput.value;

      button.disabled = true;
      button.textContent = "Joining…";
      setStatus(statusEl, "", null);

      try {
        var res = await insertSignup(payload);

        if (res.status === 201 || res.status === 200 || res.status === 204) {
          form.reset();
          syncCardFromForm(); // reset personalization back to default too
          button.textContent = "You're on the list ✓";
          setStatus(
            statusEl,
            "You're on the waitlist. We'll email " + email +
              " when it's your turn — no spam in between.",
            "success"
          );
          return;
        }

        if (res.status === 409) {
          setStatus(statusEl, "You're already on the list — we've got this email saved.", "success");
        } else if (res.status === 401 || res.status === 403) {
          setStatus(statusEl, "We couldn't save that right now. Please try again shortly.", "error");
        } else {
          var dup = false;
          try {
            var data = await res.json();
            if (data && data.code === "23505") dup = true;
          } catch (_) {}
          setStatus(
            statusEl,
            dup
              ? "You're already on the list — we've got this email saved."
              : "Something went wrong on our end. Please try again.",
            dup ? "success" : "error"
          );
        }
      } catch (err) {
        setStatus(statusEl, "Couldn't reach the server — check your connection and try again.", "error");
      } finally {
        if (button.textContent === "Joining…") button.textContent = defaultLabel;
        button.disabled = false;
      }
    });
  }

  wireForm(document.getElementById("waitlist"));
  wireForm(document.getElementById("waitlist-closing"));

  /* -------------------------------------------- hero-card personalization ---

     A small, curated role → example set (not generated per load). Selecting a
     role swaps the matched person, the shared-ground line, the thread style,
     and reseeds a believable match %. Typing a first name updates the "you"
     side of the thread live. */

  var EXAMPLES = {
    _default: {
      meta: "kept note · sf climate week",
      name: "Amara Osei", first: "amara",
      descriptor: "co-founder · tidal carbon startup",
      ground: "both backing early ocean-carbon teams",
    },
    Founder: {
      meta: "kept note · sf climate week",
      name: "Priya Nair", first: "priya",
      descriptor: "partner · early-stage climate fund",
      ground: "she funds the exact stage you're raising at",
    },
    Investor: {
      meta: "kept note · founder dinner",
      name: "Daniel Cho", first: "daniel",
      descriptor: "founder · grid-storage startup",
      ground: "raising in the space your last memo covered",
    },
    Sales: {
      meta: "kept note · saas meetup",
      name: "Rosa Méndez", first: "rosa",
      descriptor: "vp ops · mid-market logistics",
      ground: "her team is scoping the problem you solve",
    },
    Recruiter: {
      meta: "kept note · engineering mixer",
      name: "Tomás Alvarez", first: "tomás",
      descriptor: "staff engineer · payments background",
      ground: "fits the senior role you're trying to fill",
    },
    Student: {
      meta: "kept note · campus talk",
      name: "Lena Park", first: "lena",
      descriptor: "alum · research lead in robotics",
      ground: "works in the field you're heading into",
    },
    Consultant: {
      meta: "kept note · industry summit",
      name: "Mark Reilly", first: "mark",
      descriptor: "coo · regional healthcare group",
      ground: "owns the change you were brought in to advise",
    },
    "Event Organizer": {
      meta: "kept note · last year's summit",
      name: "Hana Suzuki", first: "hana",
      descriptor: "speaker · two events back",
      ground: "worth bringing back to keynote this year",
    },
    "Community Leader": {
      meta: "kept note · community meetup",
      name: "Ifeoma Eze", first: "ifeoma",
      descriptor: "member · building in fintech",
      ground: "perfect to introduce to your fintech circle",
    },
    Other: null, // falls back to _default
  };

  var card = document.getElementById("memoryCard");
  var fnameInput = document.getElementById("fname");
  var roleSelect = document.getElementById("role");

  if (card) {
    var el = {
      meta: card.querySelector("[data-meta]"),
      name: card.querySelector("[data-name]"),
      descriptor: card.querySelector("[data-descriptor]"),
      you: card.querySelector("[data-you]"),
      them: card.querySelector("[data-them]"),
      thread: card.querySelector("[data-thread]"),
      pct: card.querySelector("[data-pct]"),
      ground: card.querySelector("[data-ground]"),
    };

    var prefersReduced =
      window.matchMedia &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    function youName() {
      var v = (fnameInput && fnameInput.value ? fnameInput.value : "").trim();
      return v ? v.toLowerCase() : "you";
    }

    // 78–94, with the thread style following the strength band.
    function reseedMatch() {
      var pct = 78 + Math.floor(Math.random() * 17);
      var style = pct >= 89 ? "thread-solid" : pct >= 84 ? "thread-dashed" : "thread-dotted";
      el.pct.textContent = pct + "%";
      el.thread.className = "thread-line " + style;
    }

    function writeExample(ex) {
      el.meta.textContent = ex.meta;
      el.name.textContent = ex.name;
      el.descriptor.textContent = ex.descriptor;
      el.ground.textContent = ex.ground;
      el.them.textContent = ex.first;
      el.you.textContent = youName();
    }

    function applyRole(roleValue, reseed) {
      var ex = EXAMPLES[roleValue] || EXAMPLES._default;
      var commit = function () {
        writeExample(ex);
        if (reseed) reseedMatch();
      };
      if (prefersReduced) {
        commit();
        return;
      }
      // brief, restrained crossfade
      card.classList.add("is-swapping");
      window.setTimeout(function () {
        commit();
        card.classList.remove("is-swapping");
      }, 130);
    }

    // Live name update — instant, no per-keystroke animation.
    if (fnameInput) {
      fnameInput.addEventListener("input", function () {
        el.you.textContent = youName();
      });
    }

    // Role change — swap the example + reseed the match.
    if (roleSelect) {
      roleSelect.addEventListener("change", function () {
        applyRole(roleSelect.value, true);
      });
    }

    // Reset hook used after a successful signup.
    window.__syncCardFromForm = function () {
      applyRole(roleSelect && roleSelect.value ? roleSelect.value : "_default", false);
    };
  }

  // No-op safe wrapper (card may be absent if markup changes).
  function syncCardFromForm() {
    if (typeof window.__syncCardFromForm === "function") window.__syncCardFromForm();
  }
})();
