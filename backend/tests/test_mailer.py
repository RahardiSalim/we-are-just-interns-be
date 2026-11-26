"""Decision emails: who gets which message, what's in it, and sending over SMTP. Runs offline."""

import re
from html import escape

from app.core import config
from app.services import email_content, mailer

TICKET = email_content.ticket_number("BZaGfiK1TjfK4fHyJavs")
ARGS = ("Rani", "GR-DEMO-1", "26 Nov 2026, 19.30 WIB", TICKET)
CUSTOMER, DRIVER = ("contact", "none"), ("contact", "warn", "suspend", "none")
ALL = {e for c in CUSTOMER for d in DRIVER for e in email_content.decision_emails(c, d)}


def test_ticket_number_is_short_and_readable():
    assert TICKET == "GS-BZAG-FIK1"
    assert email_content.ticket_number("demo-incident-1") == "GS-DEMO-INCI"  # same rule as dashboard ticketNo
    # The seeded cases use Firestore-style IDs, so each gets its own number and ticket search finds one case.
    from app.services import seed
    import inspect
    ids = re.findall(r'"([A-Za-z0-9]{20})"', inspect.getsource(seed))
    assert len(ids) == 5 and len({email_content.ticket_number(i) for i in ids}) == 5
    assert email_content.ticket_number("K7QM2XRAp9LbT3vWc8Ne") == "GS-K7QM-2XRA"


def test_the_rider_always_hears_back_and_the_driver_only_when_there_is_a_driver_decision():
    for c in CUSTOMER:
        for d in DRIVER:
            who = [e.to for e in email_content.decision_emails(c, d)]
            assert who == (["rider", "driver"] if d != "none" else ["rider"]), (c, d)


def test_the_rider_email_follows_the_strongest_decision():
    outcome = lambda c, d: email_content.decision_emails(c, d)[0].outcome
    assert outcome("contact", "suspend") == "A safety agent will contact you"
    assert outcome("none", "warn") == outcome("none", "suspend") == "Reviewed, action taken"
    assert outcome("none", "contact") == "Reviewed, following up with the driver"
    assert outcome("none", "none") == "Reviewed, no further action"


def test_emails_greet_by_name_and_carry_the_ride_details_in_both_versions():
    for e in ALL:
        for body in (email_content.text(e, *ARGS), email_content.html(e, *ARGS)):
            assert "Hi Rani," in body
            for part in ("GR-DEMO-1", "26 Nov 2026, 19.30 WIB", TICKET, e.outcome, e.sign_off):
                assert part in body
            assert "{order}" not in body


def test_a_note_becomes_the_safety_team_message_and_without_one_the_full_template_is_sent():
    e = email_content.decision_emails("none", "warn")[1]
    with_note = email_content.html(e, *ARGS, note="Mohon jaga sikap.\nTerima kasih.")
    without = email_content.html(e, *ARGS)
    assert email_content.MESSAGE_TITLE in with_note and "Mohon jaga sikap.<br>Terima kasih." in with_note
    assert email_content.MESSAGE_TITLE not in without
    assert escape(e.paragraphs[1]) in without and escape(e.paragraphs[1]) not in with_note  # the two templates differ
    assert email_content.MESSAGE_TITLE not in email_content.html(e, *ARGS, note="   ")  # blank counts as no note


def test_html_escapes_names_and_notes():
    e = email_content.decision_emails("none", "none")[0]
    assert "<script>" not in email_content.html(e, "<script>", *ARGS[1:], note="<script>alert(1)</script>")


class FakeSMTP:
    sent: list = []

    def __init__(self, host, port, timeout):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def starttls(self):
        pass

    def login(self, user, password):
        pass

    def send_message(self, msg):
        FakeSMTP.sent.append(msg)


def test_without_smtp_host_nothing_is_sent(monkeypatch):
    monkeypatch.setattr(config, "SMTP_HOST", "")
    monkeypatch.setattr(mailer.smtplib, "SMTP", FakeSMTP)
    FakeSMTP.sent.clear()
    mailer.send("rider1@gosafe.test", "Hi", "Body")
    assert FakeSMTP.sent == []


def test_send_attaches_html_with_a_plain_text_copy(monkeypatch):
    monkeypatch.setattr(config, "SMTP_HOST", "smtp.test")
    monkeypatch.setattr(mailer.smtplib, "SMTP", FakeSMTP)
    FakeSMTP.sent.clear()
    e = email_content.decision_emails("none", "none")[0]
    mailer.send("rider1@gosafe.test", "Update on your report", email_content.text(e, *ARGS), email_content.html(e, *ARGS))
    (msg,) = FakeSMTP.sent
    assert (msg["To"], msg["Subject"]) == ("rider1@gosafe.test", "Update on your report")
    plain, rich = msg.iter_parts()
    assert (plain.get_content_type(), rich.get_content_type()) == ("text/plain", "multipart/related")
    types = [p.get_content_type() for p in rich.iter_parts()]
    assert types[0] == "text/html" and set(types[1:]) == {"image/png"}  # the logo and the picture, inline
    assert {p["Content-ID"] for p in rich.iter_parts() if p.get_content_type() == "image/png"} == {"<gosafe-mark>", "<icon-shield>"}


def test_every_email_picture_exists_and_reporters_get_the_illustration():
    for e in {*ALL, email_content.SOS_RECEIVED}:
        assert mailer.asset(e.art).exists(), e.art
        assert e.art.startswith("art-") == (e.to != "driver" and e.outcome != "Reviewed, no further action"), e.subject


def test_only_rider_emails_carry_the_emergency_number():
    for e in ALL:
        assert ("112" in email_content.html(e, *ARGS)) == (e.to == "rider")


def test_sos_email_confirms_the_ticket_and_gives_the_emergency_number():
    e = email_content.SOS_RECEIVED
    for body in (email_content.text(e, *ARGS), email_content.html(e, *ARGS)):
        for part in ("Hi Rani,", "on it", "Priority ticket, being processed", TICKET, "112", "SAPA 129",
                     "not your fault", "confidential safety report"):
            assert part in body
    assert email_content.subject(e, "GR-DEMO-1", TICKET) == "We've received your safety report (ticket GS-BZAG-FIK1)"


def test_sos_subject_never_says_what_happened():
    subject = email_content.subject(email_content.SOS_RECEIVED, "GR-DEMO-1", "x").lower()
    assert not any(word in subject for word in ("sexual", "harass", "assault", "violence", "sos"))


def test_a_broken_smtp_server_never_raises(monkeypatch):
    monkeypatch.setattr(config, "SMTP_HOST", "smtp.test")

    def boom(*_a, **_k):
        raise OSError("connection refused")

    monkeypatch.setattr(mailer.smtplib, "SMTP", boom)
    mailer.send("rider1@gosafe.test", "Hi", "Body")


class FakeResponse:
    def __init__(self, status_code=200, text=""):
        self.status_code, self.text = status_code, text


def test_resend_sends_over_https_with_the_pictures_inline_and_no_smtp(monkeypatch):
    sent = []
    monkeypatch.setattr(config, "RESEND_API_KEY", "re_test")
    monkeypatch.setattr(config, "SMTP_HOST", "smtp.test")
    monkeypatch.setattr(mailer.smtplib, "SMTP", FakeSMTP)
    FakeSMTP.sent.clear()
    monkeypatch.setattr(mailer.httpx, "post", lambda url, headers, json, timeout: sent.append((url, headers, json)) or FakeResponse())
    e = email_content.decision_emails("none", "none")[0]
    mailer.send("rider1@gosafe.test", "Update on your report", email_content.text(e, *ARGS), email_content.html(e, *ARGS))
    ((url, headers, body),) = sent
    assert url == "https://api.resend.com/emails" and headers["Authorization"] == "Bearer re_test"
    assert (body["from"], body["to"], body["subject"]) == (config.RESEND_FROM, ["rider1@gosafe.test"], "Update on your report")
    assert "Hi Rani," in body["text"] and "Hi Rani," in body["html"]
    cids = set(re.findall(r'src="cid:([\w-]+)"', body["html"]))
    assert cids and {a["content_id"] for a in body["attachments"]} == cids  # every picture the HTML uses is attached inline
    assert FakeSMTP.sent == []


def test_a_resend_error_never_raises(monkeypatch):
    monkeypatch.setattr(config, "RESEND_API_KEY", "re_test")
    monkeypatch.setattr(mailer.httpx, "post", lambda *_a, **_k: FakeResponse(403, "not allowed to send to this address"))
    mailer.send("someone@else.test", "Hi", "Body")

    def boom(*_a, **_k):
        raise OSError("no network")

    monkeypatch.setattr(mailer.httpx, "post", boom)
    mailer.send("someone@else.test", "Hi", "Body")


def test_without_any_mail_setting_nothing_is_sent(monkeypatch):
    monkeypatch.setattr(config, "RESEND_API_KEY", "")
    monkeypatch.setattr(config, "SMTP_HOST", "")
    monkeypatch.setattr(mailer.httpx, "post", lambda *_a, **_k: (_ for _ in ()).throw(AssertionError("must not call Resend")))
    mailer.send("rider1@gosafe.test", "Hi", "Body")
