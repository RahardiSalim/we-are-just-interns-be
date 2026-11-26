"""What the decision emails say, and how they look.

Look: contracts/DESIGN.md (Gojek Asphalt + Brand Book 2019), the same tokens as the dashboard, inlined because
mail apps ignore stylesheets. Copy: DESIGN.md "Writing": clear and empathetic, never witty; rider emails never
blame or name the driver. The agent's note for each person is a message from the safety team: with a note the email
is the short template plus that message; without one it is the full standalone template, so no section is empty."""

from dataclasses import dataclass
from html import escape
from typing import Literal

# DESIGN.md tokens (light theme only: mail apps don't follow our dark tokens).
BRAND, BRAND_STRONG, BRAND_DEEP, BRAND_TINT = "#00AA13", "#008A10", "#257226", "#E6F7E8"
CANVAS, SURFACE, LINE, MUTED, INK = "#FFFFFF", "#F7F7F7", "#D9D9D6", "#63666A", "#101820"
WARN, WARN_TINT, HIGH, HIGH_TINT, SOS, SOS_TINT = "#FF8F1C", "#FFF4E5", "#D22730", "#F2D4D7", "#862633", "#F3E4E6"
FONT = "font-family:'Plus Jakarta Sans',Helvetica,Arial,sans-serif;"

Tone = Literal["success", "neutral", "warn", "high"]
# Badge: (background, text, border). Meaning colours only say how serious it is (DESIGN.md "Safety meaning").
TONES: dict[Tone, tuple[str, str, str]] = {
    "success": (BRAND_TINT, BRAND_DEEP, BRAND),
    "neutral": (SURFACE, INK, LINE),
    "warn": (WARN_TINT, INK, WARN),
    "high": (HIGH_TINT, INK, HIGH),
}

LOGO_CID = "gosafe-mark"  # the shield in app/assets/gosafe-mark.png, attached inline by mailer.send
FOOTER = "This is an automated message about your Gojek ride, so replies to this address aren't read."
CONFIDENTIAL = ("This email is about a confidential safety report. If it reached you by mistake, "
                "please delete it and don't forward it.")
EMERGENCY = "In an emergency, call 112 right away."


@dataclass(frozen=True)
class Email:
    to: Literal["rider", "driver", "reporter"]  # reporter: whoever pressed SOS
    subject: str
    headline: str
    paragraphs: tuple[str, ...]
    outcome: str
    tone: Tone
    next_steps: tuple[str, ...]
    sign_off: str = "Gojek Safety Team"
    # Picture under the header, an image in app/assets attached inline: "art-support" (the Gojek support
    # illustration, for people who reported something) or an Asphalt-style icon tile ("icon-...").
    art: str = "art-support"

    @property
    def emergency(self) -> bool:
        return self.to != "driver"  # the 112 box: riders, and anyone who pressed SOS

    @property
    def confidential(self) -> bool:
        return self.to == "reporter"  # SOS reports can be about sexual violence: extra privacy line in the footer


_RIDER_THANKS = (
    "Thank you for telling us about your ride. Our safety team listened to the flagged moments "
    "and reviewed your report in full."
)
_RIDER_NEXT = (
    "You don't need to do anything else.",
    "If something else happened, report it from the Gojek app any time.",
)
_RIDER_ACTION_TAKEN = Email(
    "rider",
    "Update on your report for ride {order}",
    "We've reviewed your ride",
    (_RIDER_THANKS, "We've taken action with the driver in line with Gojek's partner code of conduct. "
     "To protect everyone's privacy, we can't share the details."),
    "Reviewed, action taken",
    "success",
    _RIDER_NEXT,
)
_DRIVER = {"sign_off": "Gojek Partner Safety Team"}

# The rider always hears the outcome; which email depends on both decisions (see decision_emails).
RIDER_EMAILS: dict[str, Email] = {
    "contact": Email(
            "rider",
            "We'd like to check in on you after ride {order}",
            "We're here for you",
            ("Thank you for telling us about your ride. Your safety matters to us, and our safety team "
             "has reviewed what happened.",
             "A member of our team will contact you shortly to check on you and talk through the support we can offer."),
            "A safety agent will contact you",
            "success",
            ("Keep your phone nearby. We'll reach out soon.",),
        ),
    "action": _RIDER_ACTION_TAKEN,
    "follow_up": Email(
            "rider",
            "Update on your report for ride {order}",
            "We're following up on your ride",
            (_RIDER_THANKS, "Our safety team is following up with the driver directly. "
             "To protect everyone's privacy, we can't share the details."),
            "Reviewed, following up with the driver",
            "success",
            _RIDER_NEXT,
        ),
    "none": Email(
            "rider",
            "Update on your report for ride {order}",
            "We've reviewed your ride",
            (_RIDER_THANKS, "We didn't find anything that needs further action this time. "
             "We take every report seriously, so thank you for speaking up."),
            "Reviewed, no further action",
            "neutral",
            _RIDER_NEXT,
            art="icon-shield",
        ),
}

DRIVER_EMAILS: dict[str, Email] = {
    "contact": Email(
            "driver",
            "Our safety team would like to talk to you about ride {order}",
            "We'd like to talk to you about a recent ride",
            ("Our safety team reviewed ride {order} after it was flagged during the trip.",
             "A member of our team will contact you shortly to hear your side and talk it through. "
             "This is not a warning or a suspension."),
            "A safety agent will contact you",
            "neutral",
            ("Keep your phone nearby so we can reach you.",
             "If you can't talk when we call, we'll try again."),
            art="icon-chat",
            **_DRIVER,
        ),
    "warn": Email(
            "driver",
            "Formal warning about ride {order}",
            "A formal warning about a recent ride",
            ("Our safety team reviewed ride {order} after it was flagged during the trip.",
             "Part of the conversation didn't meet Gojek's partner code of conduct. "
             "This is a formal warning, and it has been added to your partner record."),
            "Formal warning",
            "warn",
            ("Keep every conversation with customers polite and professional.",
             "Another confirmed report may lead to your account being paused.",
             "If you think this is a mistake, contact partner support from the Gojek Driver app."),
            art="icon-alert",
            **_DRIVER,
        ),
    "suspend": Email(
            "driver",
            "Your account is paused while we review ride {order}",
            "Your account is paused",
            ("Our safety team reviewed ride {order} after it was flagged during the trip.",
             "While we investigate, your account is paused and you can't take orders. "
             "We'll contact you with the outcome once the review is finished."),
            "Account paused during investigation",
            "high",
            ("You don't need to do anything right now.",
             "We'll contact you as soon as the review is finished.",
             "If you think this is a mistake, contact partner support from the Gojek Driver app."),
            art="icon-lock",
            **_DRIVER,
        ),
}


def decision_emails(customer: str, driver: str) -> tuple[Email, ...]:
    """The rider's email (contacting them wins, then action on the driver, then a follow-up, else no action),
    plus the driver's email when the driver decision is anything but "none"."""
    outcome = ("contact" if customer == "contact" else "action" if driver in ("warn", "suspend")
               else "follow_up" if driver == "contact" else "none")
    return (RIDER_EMAILS[outcome], *((DRIVER_EMAILS[driver],) if driver in DRIVER_EMAILS else ()))


# Sent right after someone presses SOS and the ticket is created, before any agent has looked at it.
# SOS reports can be about sexual violence, so the copy is trauma-informed: the subject says nothing about
# what happened (emails show up on lock screens), no blame, the reporter decides how much to share,
# and it points to free support outside Gojek. It promises nothing the system doesn't do.
SOS_RECEIVED = Email(
    "reporter",
    "We've received your safety report (ticket {ticket})",
    "We've received your report, and we're on it",
    ("Thank you for reaching out. You did the right thing by pressing SOS. We've opened a priority safety ticket "
     "for ride {order}, and our safety team is reviewing it now.",
     "Whatever happened, it is not your fault. Your report is handled confidentially and is seen only by "
     "Gojek's safety team.",
     "You don't need to explain anything again: the ticket already has the details of your ride."),
    "Priority ticket, being processed",
    "success",
    ("A member of our safety team will contact you through the Gojek app or by phone. You can share as much "
     "or as little as you want.",
     "If you'd like to talk to someone outside Gojek, SAPA 129 gives free, confidential support for women and "
     "children: call 129 or WhatsApp 08111 129 129.",
     "Keep your phone nearby so we can reach you."),
)


def subject(e: Email, order: str, ticket: str) -> str:
    return e.subject.format(order=order, ticket=ticket)


def ticket_number(incident_id: str) -> str:
    """What agents and customers read out on the phone: GS-XXXX-XXXX from the incident ID (dashboard: labels.ts)."""
    code = "".join(c for c in incident_id if c.isalnum()).upper()
    return f"GS-{code[:4]}-{code[4:8]}"


def details(order: str, ride_time: str, ticket: str) -> list[tuple[str, str]]:
    return [("Ticket number", ticket), ("Order ID", order), ("Ride", ride_time)]


def _body(e: Email, order: str, note: str) -> list[str]:
    """Without a note: the full template. With one: its opening line; the note follows as the team's message."""
    return [p.format(order=order) for p in (e.paragraphs[:1] if note.strip() else e.paragraphs)]


MESSAGE_TITLE = "A message from the safety team who reviewed your ride"


def text(e: Email, name: str, order: str, ride_time: str, ticket: str, note: str = "") -> str:
    """Plain-text version, for mail apps that don't show HTML."""
    rows = "\n".join(f"{k}: {v}" for k, v in [("Outcome", e.outcome), *details(order, ride_time, ticket)])
    steps = "\n".join(f"{i}. {s}" for i, s in enumerate(e.next_steps, 1))
    body = "\n\n".join(_body(e, order, note)) + (f"\n\n{MESSAGE_TITLE}:\n{note.strip()}" if note.strip() else "")
    sos = f"\n\n{EMERGENCY}" if e.emergency else ""
    return (f"Hi {name},\n\n{e.headline}\n\n{body}\n\n{rows}\n\nWhat happens next\n{steps}{sos}\n\n"
            f"Kind regards,\n{e.sign_off}\n\n--\nGoSafe, ride safety for GoRide and GoCar\n{FOOTER}"
            + (f"\n{CONFIDENTIAL}" if e.confidential else ""))


def _p(content: str, size: int, line: int, color: str = INK, weight: int = 400, margin: str = "0") -> str:
    return f'<p style="margin:{margin};{FONT}font-size:{size}px;line-height:{line}px;font-weight:{weight};color:{color};">{content}</p>'


def html(e: Email, name: str, order: str, ride_time: str, ticket: str, note: str = "") -> str:
    """Table layout with inline styles: the only kind Gmail and Outlook render reliably. 600px, 4px grid.
    Green header with a curved bottom like the dashboard; dark header for a warning or a suspension."""
    hero = INK if e.tone in ("warn", "high") else BRAND_STRONG
    dot = {"success": BRAND, "neutral": MUTED, "warn": WARN, "high": HIGH}[e.tone]
    table = 'role="presentation" width="100%" cellpadding="0" cellspacing="0"'

    paras = "".join(_p(escape(p), 16, 26, margin="0 0 16px") for p in _body(e, order, note))
    quote = ""
    if note.strip():
        message = escape(note.strip()).replace("\n", "<br>")
        quote = (
            f'<table {table} style="margin:4px 0 24px;background:{SURFACE};border-radius:12px;"><tr>'
            f'<td style="width:4px;background:{BRAND};border-radius:12px 0 0 12px;"></td>'
            f'<td style="padding:16px 20px;">'
            f'{_p(escape(MESSAGE_TITLE), 13, 18, BRAND_DEEP, 700, "0 0 8px")}'
            f'<p style="margin:0;{FONT}font-size:16px;line-height:26px;color:{INK};">'
            f'<span style="color:{BRAND};font-size:24px;line-height:16px;font-weight:700;">&ldquo;</span>{message}</p>'
            f"</td></tr></table>"
        )

    summary = "".join(
        f'<td width="33%" style="padding:14px 16px;vertical-align:top;{"border-left:1px solid " + LINE + ";" if i else ""}">'
        f'{_p(escape(k), 12, 16, MUTED, margin="0 0 4px")}{_p(escape(v), 15, 20, INK, 700)}</td>'
        for i, (k, v) in enumerate(details(order, ride_time, ticket))
    )

    steps = "".join(
        f'<tr><td style="width:40px;vertical-align:top;padding:0 0 14px;">'
        f'<div style="width:28px;height:28px;border-radius:999px;background:{BRAND_TINT};color:{BRAND_DEEP};text-align:center;'
        f'{FONT}font-size:13px;line-height:28px;font-weight:700;">{i}</div></td>'
        f'<td style="vertical-align:top;padding:4px 0 14px;{FONT}font-size:15px;line-height:22px;color:{INK};">{escape(s)}</td></tr>'
        for i, s in enumerate(e.next_steps, 1)
    )

    picture = (
        f'<img src="cid:{e.art}" width="536" alt="" style="display:block;width:100%;max-width:536px;height:auto;border:0;margin:0 0 20px;">'
        if e.art.startswith("art-") else
        f'<img src="cid:{e.art}" width="80" height="80" alt="" style="display:block;border:0;margin:-8px 0 8px -12px;">'
    )

    help_cards = (
        f'<tr><td style="padding:8px 32px 8px;"><table {table}><tr>'
        f'<td width="50%" style="padding:16px;background:{SOS_TINT};border-radius:12px;vertical-align:top;">'
        f'{_p("Need help now?", 14, 20, SOS, 700, "0 0 4px")}{_p(escape(EMERGENCY), 14, 20)}</td>'
        f'<td style="width:12px;"></td>'
        f'<td width="50%" style="padding:16px;background:{SURFACE};border-radius:12px;vertical-align:top;">'
        f'{_p("Something else happened?", 14, 20, INK, 700, "0 0 4px")}{_p("Report it from the Gojek app any time.", 14, 20)}</td>'
        f"</tr></table></td></tr>"
        if e.emergency else ""
    )

    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light only"><meta name="supported-color-schemes" content="light">
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;700&display=swap" rel="stylesheet">
<title>{escape(subject(e, order, ticket))}</title></head>
<body style="margin:0;padding:0;background:{SURFACE};">
<div style="display:none;max-height:0;overflow:hidden;">{escape(e.headline)}. {escape(e.outcome)}. Ticket {escape(ticket)}.</div>
<table {table} style="background:{SURFACE};">
<tr><td align="center" style="padding:32px 12px;">
<table {table} style="max-width:600px;background:{CANVAS};border:1px solid {LINE};border-radius:16px;overflow:hidden;">

  <tr><td style="background:{hero};padding:24px 32px 28px;">
    <table {table}><tr>
      <td style="vertical-align:middle;">
        <table role="presentation" cellpadding="0" cellspacing="0"><tr>
          <td style="width:36px;height:36px;background:{CANVAS};border-radius:999px;text-align:center;vertical-align:middle;">
            <img src="cid:{LOGO_CID}" width="22" height="22" alt="" style="display:inline-block;border:0;vertical-align:middle;"></td>
          <td style="padding-left:10px;vertical-align:middle;{FONT}font-size:18px;line-height:24px;font-weight:700;color:{CANVAS};">GoSafe
            <span style="font-size:13px;font-weight:400;">&nbsp;by Gojek</span></td>
        </tr></table>
      </td>
      <td align="right" style="vertical-align:middle;">
        <span style="display:inline-block;border:1px solid {CANVAS};border-radius:999px;padding:4px 12px;{FONT}font-size:12px;line-height:16px;font-weight:600;color:{CANVAS};">{escape(ticket)}</span>
      </td>
    </tr></table>
    {_p(f"Hi {escape(name)},", 16, 24, CANVAS, margin="28px 0 4px")}
    <h1 style="margin:0 0 16px;{FONT}font-size:28px;line-height:36px;font-weight:700;color:{CANVAS};">{escape(e.headline)}</h1>
    <span style="display:inline-block;background:{CANVAS};border-radius:999px;padding:6px 14px 6px 12px;{FONT}font-size:13px;line-height:18px;font-weight:700;color:{INK};">
      <span style="display:inline-block;width:8px;height:8px;border-radius:999px;background:{dot};margin-right:6px;"></span>{escape(e.outcome)}</span>
  </td></tr>
  <tr><td style="background:{hero};font-size:0;line-height:0;">
    <div style="height:24px;background:{CANVAS};border-radius:24px 24px 0 0;">&nbsp;</div>
  </td></tr>

  <tr><td style="padding:4px 32px 0;">
    {picture}
    {paras}
    {quote}
    <table {table} style="margin:0 0 28px;background:{SURFACE};border-radius:12px;"><tr>{summary}</tr></table>
  </td></tr>

  <tr><td style="padding:0 32px 8px;">
    {_p("What happens next", 18, 24, INK, 700, "0 0 16px")}
    <table {table}>{steps}</table>
  </td></tr>
  {help_cards}
  <tr><td style="padding:20px 32px 32px;">
    {_p("Kind regards,", 15, 22, MUTED)}
    {_p(escape(e.sign_off), 16, 24, INK, 700)}
  </td></tr>

</table>

<table {table} style="max-width:600px;">
  <tr><td align="center" style="padding:24px 24px 0;">
    <img src="cid:{LOGO_CID}" width="20" height="20" alt="" style="display:block;border:0;margin:0 auto 8px;">
    {_p(f'<strong style="color:{BRAND_DEEP};">GoSafe</strong> &middot; Ride safety for GoRide and GoCar', 12, 18, MUTED, margin="0 0 4px")}
    {_p(escape(FOOTER), 12, 18, MUTED)}
    {_p(escape(CONFIDENTIAL), 12, 18, MUTED, margin="4px 0 0") if e.confidential else ""}
  </td></tr>
</table>

</td></tr></table>
</body></html>"""
