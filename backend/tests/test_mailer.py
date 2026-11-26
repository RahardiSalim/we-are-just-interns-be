"""Decision emails: who gets which message, what's in it, and sending over SMTP. Runs offline."""

from app.core import config
from app.services import email_content, mailer

ARGS = ("Rani", "GR-DEMO-1", "26 Nov 2026, 19.30 WIB", "demo-incident-1")


def test_every_decision_tells_the_rider_and_only_actions_on_the_driver_tell_the_driver():
    for action, emails in email_content.DECISION_EMAILS.items():
        who = [e.to for e in emails]
        assert "rider" in who
        assert ("driver" in who) == (action in ("warn_driver", "suspend_driver"))


def test_emails_greet_by_name_and_carry_the_ride_details_in_both_versions():
    for emails in email_content.DECISION_EMAILS.values():
        for e in emails:
            for body in (email_content.text(e, *ARGS), email_content.html(e, *ARGS)):
                assert "Hi Rani," in body
                for part in ("GR-DEMO-1", "26 Nov 2026, 19.30 WIB", "demo-incident-1", e.outcome, e.sign_off):
                    assert part in body
                assert "{order}" not in body


def test_html_escapes_names():
    e = email_content.DECISION_EMAILS["dismiss"][0]
    assert "<script>" not in email_content.html(e, "<script>", *ARGS[1:])


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
    e = email_content.DECISION_EMAILS["dismiss"][0]
    mailer.send("rider1@gosafe.test", "Update on your report", email_content.text(e, *ARGS), email_content.html(e, *ARGS))
    (msg,) = FakeSMTP.sent
    assert (msg["To"], msg["Subject"]) == ("rider1@gosafe.test", "Update on your report")
    plain, rich = msg.iter_parts()
    assert (plain.get_content_type(), rich.get_content_type()) == ("text/plain", "multipart/related")
    assert [p.get_content_type() for p in rich.iter_parts()] == ["text/html", "image/png"]  # the shield, inline


def test_only_rider_emails_carry_the_emergency_number():
    for emails in email_content.DECISION_EMAILS.values():
        for e in emails:
            assert ("112" in email_content.html(e, *ARGS)) == (e.to == "rider")


def test_sos_email_confirms_the_ticket_and_gives_the_emergency_number():
    e = email_content.SOS_RECEIVED
    for body in (email_content.text(e, *ARGS), email_content.html(e, *ARGS)):
        for part in ("Hi Rani,", "on it", "Priority ticket, being processed", "#demo-incident-1", "112", "SAPA 129",
                     "not your fault", "confidential safety report"):
            assert part in body
    assert email_content.subject(e, "GR-DEMO-1", "demo-incident-1") == "We've received your safety report (ticket #demo-incident-1)"


def test_sos_subject_never_says_what_happened():
    subject = email_content.subject(email_content.SOS_RECEIVED, "GR-DEMO-1", "x").lower()
    assert not any(word in subject for word in ("sexual", "harass", "assault", "violence", "sos"))


def test_a_broken_smtp_server_never_raises(monkeypatch):
    monkeypatch.setattr(config, "SMTP_HOST", "smtp.test")

    def boom(*_a, **_k):
        raise OSError("connection refused")

    monkeypatch.setattr(mailer.smtplib, "SMTP", boom)
    mailer.send("rider1@gosafe.test", "Hi", "Body")
