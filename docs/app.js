/* Linkd waitlist — single inline Supabase REST insert (no client lib).
   The anon public key is safe to expose: per RLS it can INSERT only, never
   read/update/delete (see the waitlist_signups policy). */

(function () {
  "use strict";

  var SUPABASE_URL = "https://rtcxdwqdewudrzctwlbo.supabase.co";
  // anon (public) key — write-only against waitlist_signups by design.
  var SUPABASE_ANON_KEY =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ0Y3hkd3FkZXd1ZHJ6Y3R3bGJvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE5MDUyOTIsImV4cCI6MjA5NzQ4MTI5Mn0.WnZD5_RfNGsQd0d6xZ9Mp8Y1P-HQVG6o-HqxZJECni8";

  var ENDPOINT = SUPABASE_URL + "/rest/v1/waitlist_signups";

  // Footer year
  var yearEl = document.getElementById("year");
  if (yearEl) yearEl.textContent = String(new Date().getFullYear());

  function setStatus(el, message, kind) {
    el.textContent = message;
    el.classList.remove("is-error", "is-success");
    if (kind) el.classList.add("is-" + kind);
  }

  async function insertSignup(payload) {
    var res = await fetch(ENDPOINT, {
      method: "POST",
      headers: {
        apikey: SUPABASE_ANON_KEY,
        Authorization: "Bearer " + SUPABASE_ANON_KEY,
        "Content-Type": "application/json",
        // We have no read access (insert-only RLS), so don't ask for the row back.
        Prefer: "return=minimal",
      },
      body: JSON.stringify(payload),
    });
    return res;
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
          button.textContent = "You're on the list ✓";
          setStatus(
            statusEl,
            "You're on the waitlist. We'll email " + email +
              " when it's your turn — no spam in between.",
            "success"
          );
          return; // leave the button in its confirmed state
        }

        if (res.status === 409) {
          // unique email violation — already signed up
          setStatus(
            statusEl,
            "You're already on the list — we've got this email saved.",
            "success"
          );
        } else if (res.status === 401 || res.status === 403) {
          setStatus(
            statusEl,
            "We couldn't save that right now. Please try again shortly.",
            "error"
          );
        } else {
          // Inspect the body for a duplicate code, otherwise generic.
          var dup = false;
          try {
            var data = await res.json();
            if (data && data.code === "23505") dup = true;
          } catch (_) {}
          if (dup) {
            setStatus(
              statusEl,
              "You're already on the list — we've got this email saved.",
              "success"
            );
          } else {
            setStatus(
              statusEl,
              "Something went wrong on our end. Please try again.",
              "error"
            );
          }
        }
      } catch (err) {
        setStatus(
          statusEl,
          "Couldn't reach the server — check your connection and try again.",
          "error"
        );
      } finally {
        // Restore the button unless we left it in the confirmed success state.
        if (button.textContent === "Joining…") button.textContent = defaultLabel;
        button.disabled = false;
      }
    });
  }

  wireForm(document.getElementById("waitlist"));
  wireForm(document.getElementById("waitlist-closing"));
})();
