/* Linkd landing. Supabase waitlist insert + live hero-card personalization.

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
    var nameInput = form.querySelector("input[name=fname]");
    var emailInput = form.querySelector("input[type=email]");
    var roleInput = form.querySelector("select[name=role]");
    var defaultLabel = button.getAttribute("data-default-label") || button.textContent;

    form.addEventListener("submit", async function (e) {
      e.preventDefault();

      // Name is required. Validate it first, with a specific, on-tone message.
      var name = (nameInput && nameInput.value ? nameInput.value : "").trim();
      if (!name) {
        setStatus(statusEl, "Add your first name so we know what to call you.", "error");
        if (nameInput) nameInput.focus();
        return;
      }

      var email = (emailInput.value || "").trim();
      if (!emailInput.checkValidity() || !email) {
        setStatus(statusEl, "Please enter a valid email address.", "error");
        emailInput.focus();
        return;
      }

      var payload = { email: email.toLowerCase(), first_name: name };
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
              " when it's your turn. No spam in between.",
            "success"
          );
          return;
        }

        if (res.status === 409) {
          setStatus(statusEl, "You're already on the list. We've got this email saved.", "success");
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
              ? "You're already on the list. We've got this email saved."
              : "Something went wrong on our end. Please try again.",
            dup ? "success" : "error"
          );
        }
      } catch (err) {
        setStatus(statusEl, "Couldn't reach the server. Check your connection and try again.", "error");
      } finally {
        if (button.textContent === "Joining…") button.textContent = defaultLabel;
        button.disabled = false;
      }
    });
  }

  wireForm(document.getElementById("waitlist"));

  /* -------------------------------------------- hero-card personalization ---

     A small, curated intent -> example set (not generated per load). The form's
     "what brings you here" is intent based, not job title based, so each broad
     intent still resolves to one concrete, specific match. Picking an intent
     swaps the matched person, the shared-ground line, the active thread style,
     and reseeds a believable match percentage. Typing a first name updates the
     visitor's name on both the gray "you to Linkd" line and the example match. */

  var EXAMPLES = {
    _default: {
      name: "Amara Osei", first: "amara",
      descriptor: "someone you met once, briefly",
      ground: "the detail you would have lost by next week",
    },
    building: {
      name: "Priya Nair", first: "priya",
      descriptor: "partner at a seed-stage fund",
      ground: "she writes first checks at exactly the stage you're at",
    },
    investing: {
      name: "Daniel Cho", first: "daniel",
      descriptor: "founder, grid-storage, raising now",
      ground: "building in the space your last bet was about",
    },
    hiring: {
      name: "Tomás Alvarez", first: "tomás",
      descriptor: "staff engineer, quietly open to a move",
      ground: "fits the senior role you've been trying to fill",
    },
    opportunity: {
      name: "Lena Park", first: "lena",
      descriptor: "head of eng on a team that's hiring",
      ground: "her team is opening the kind of role you want",
    },
    community: {
      name: "Ifeoma Eze", first: "ifeoma",
      descriptor: "organizer of a 2,000-person community",
      ground: "her circle overlaps the people you're gathering",
    },
    other: null, // falls back to _default
  };

  var card = document.getElementById("memoryCard");
  var fnameInput = document.getElementById("fname");
  var roleSelect = document.getElementById("role");

  if (card) {
    // There are two "you" nodes now: the gray pending line and the example
    // match thread. Both follow what the visitor types.
    var youNodes = card.querySelectorAll("[data-you]");
    var el = {
      name: card.querySelector("[data-name]"),
      descriptor: card.querySelector("[data-descriptor]"),
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

    function setYou() {
      var v = youName();
      for (var i = 0; i < youNodes.length; i++) youNodes[i].textContent = v;
    }

    // The example is an active connection, so bias to dashed/solid (84+), never
    // the sparse dotted style. That keeps it clearly distinct from the gray,
    // deliberately-unmade "you to Linkd" line above it.
    function reseedMatch() {
      var pct = 85 + Math.floor(Math.random() * 11); // 85..95
      var style = pct >= 90 ? "thread-solid" : "thread-dashed";
      el.pct.textContent = pct + "%";
      el.thread.className = "thread-line " + style;
    }

    function writeExample(ex) {
      el.name.textContent = ex.name;
      el.descriptor.textContent = ex.descriptor;
      el.ground.textContent = ex.ground;
      el.them.textContent = ex.first;
      setYou();
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

    // Live name update, instant, no per-keystroke animation.
    if (fnameInput) {
      fnameInput.addEventListener("input", setYou);
    }

    // Intent change, swap the example + reseed the match.
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
