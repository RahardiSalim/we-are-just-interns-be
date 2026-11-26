"""What the decision emails say, and how they look.

Look: contracts/DESIGN.md (Gojek Asphalt + Brand Book 2019), the same tokens as the dashboard, inlined because
mail apps ignore stylesheets. Copy: DESIGN.md "Writing": clear and empathetic, never witty; rider emails never
blame or name the driver; the agent's note is never sent."""

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

DECISION_EMAILS: dict[str, tuple[Email, ...]] = {
    "contact_rider": (
        Email(
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
    ),
    "warn_driver": (
        _RIDER_ACTION_TAKEN,
        Email(
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
            **_DRIVER,
        ),
    ),
    "suspend_driver": (
        _RIDER_ACTION_TAKEN,
        Email(
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
            **_DRIVER,
        ),
    ),
    "dismiss": (
        Email(
            "rider",
            "Update on your report for ride {order}",
            "We've reviewed your ride",
            (_RIDER_THANKS, "We didn't find anything that needs further action this time. "
             "We take every report seriously, so thank you for speaking up."),
            "Reviewed, no further action",
            "neutral",
            _RIDER_NEXT,
        ),
    ),
}


# Sent right after someone presses SOS and the ticket is created (before any agent has looked at it).
# Sent right after someone presses SOS and the ticket is created, before any agent has looked at it.
# SOS reports can be about sexual violence, so the copy is trauma-informed: the subject says nothing about
# what happened (emails show up on lock screens), no blame, the reporter decides how much to share,
# and it points to free support outside Gojek. It promises nothing the system doesn't do.
SOS_RECEIVED = Email(
    "reporter",
    "We've received your safety report (ticket #{ticket})",
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


def details(order: str, ride_time: str, case_id: str) -> list[tuple[str, str]]:
    return [("Ticket number", f"#{case_id}"), ("Order ID", order), ("Ride", ride_time)]


def text(e: Email, name: str, order: str, ride_time: str, case_id: str) -> str:
    """Plain-text version, for mail apps that don't show HTML."""
    rows = "\n".join(f"{k}: {v}" for k, v in [("Outcome", e.outcome), *details(order, ride_time, case_id)])
    steps = "\n".join(f"{i}. {s}" for i, s in enumerate(e.next_steps, 1))
    body = "\n\n".join(p.format(order=order) for p in e.paragraphs)
    sos = f"\n\n{EMERGENCY}" if e.emergency else ""
    return (f"Hi {name},\n\n{e.headline}\n\n{body}\n\n{rows}\n\nWhat happens next\n{steps}{sos}\n\n"
            f"Kind regards,\n{e.sign_off}\n\n--\nGoSafe, ride safety for GoRide and GoCar\n{FOOTER}"
            + (f"\n{CONFIDENTIAL}" if e.confidential else ""))


def _p(content: str, size: int, line: int, color: str = INK, weight: int = 400, margin: str = "0") -> str:
    return f'<p style="margin:{margin};{FONT}font-size:{size}px;line-height:{line}px;font-weight:{weight};color:{color};">{content}</p>'


def html(e: Email, name: str, order: str, ride_time: str, case_id: str) -> str:
    """Table layout with inline styles: the only kind Gmail and Outlook render reliably. Spacing on the 4px grid."""
    bg, fg, edge = TONES[e.tone]
    badge = (f'<span style="display:inline-block;background:{bg};color:{fg};border:1px solid {edge};border-radius:8px;'
             f'padding:4px 12px;{FONT}font-size:14px;line-height:20px;font-weight:600;">{escape(e.outcome)}</span>')
    paras = "".join(_p(escape(p.format(order=order)), 16, 24, margin="0 0 16px") for p in e.paragraphs)
    rows = "".join(
        f'<tr><td style="padding:4px 0;{FONT}font-size:14px;line-height:20px;color:{MUTED};width:132px;vertical-align:top;">{escape(k)}</td>'
        f'<td style="padding:4px 0;{FONT}font-size:14px;line-height:20px;font-weight:600;color:{INK};">{escape(v)}</td></tr>'
        for k, v in details(order, ride_time, case_id)
    )
    steps = "".join(
        f'<tr><td style="width:36px;vertical-align:top;padding:0 0 12px;">'
        f'<div style="width:24px;height:24px;border-radius:999px;background:{BRAND_STRONG};color:{CANVAS};text-align:center;'
        f'{FONT}font-size:12px;line-height:24px;font-weight:700;">{i}</div></td>'
        f'<td style="vertical-align:top;padding:2px 0 12px;{FONT}font-size:16px;line-height:20px;color:{INK};">{escape(s)}</td></tr>'
        for i, s in enumerate(e.next_steps, 1)
    )
    sos = (
        f'<tr><td style="padding:0 32px 24px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" '
        f'style="background:{SOS_TINT};border-radius:12px;"><tr>'
        f'<td style="width:4px;background:{SOS};border-radius:12px 0 0 12px;"></td>'
        f'<td style="padding:12px 16px;">{_p(f"<strong>Need help now?</strong> {escape(EMERGENCY)}", 14, 20)}</td>'
        f'</tr></table></td></tr>'
        if e.emergency else ""
    )
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light only"><meta name="supported-color-schemes" content="light">
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;700&display=swap" rel="stylesheet">
<title>{escape(subject(e, order, case_id))}</title></head>
<body style="margin:0;padding:0;background:{SURFACE};">
<div style="display:none;max-height:0;overflow:hidden;">{escape(e.headline)}. {escape(e.outcome)}.</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:{SURFACE};">
<tr><td align="center" style="padding:32px 16px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;">

  <tr><td style="padding:0 8px 16px;">
    <table role="presentation" cellpadding="0" cellspacing="0"><tr>
      <td style="vertical-align:middle;padding-right:8px;"><img src="cid:{LOGO_CID}" width="32" height="32" alt="" style="display:block;border:0;"></td>
      <td style="vertical-align:middle;{FONT}font-size:20px;line-height:28px;font-weight:700;color:{INK};">GoSafe</td>
      <td style="vertical-align:middle;padding-left:8px;{FONT}font-size:14px;line-height:20px;color:{MUTED};">by Gojek</td>
    </tr></table>
  </td></tr>

  <tr><td style="background:{CANVAS};border:1px solid {LINE};border-radius:16px;overflow:hidden;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
      <tr><td style="height:4px;background:{BRAND};font-size:0;line-height:0;">&nbsp;</td></tr>
      <tr><td style="padding:32px 32px 8px;">
        {_p(f"Hi {escape(name)},", 16, 24, MUTED, margin="0 0 8px")}
        <h1 style="margin:0 0 16px;{FONT}font-size:26px;line-height:36px;font-weight:700;color:{INK};">{escape(e.headline)}</h1>
        <div style="margin:0 0 24px;">{badge}</div>
        {paras}
      </td></tr>

      <tr><td style="padding:0 32px 24px;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border:1px solid {LINE};border-radius:12px;">
          <tr><td style="padding:20px;">
            {_p("Ticket details", 16, 20, weight=600, margin="0 0 12px")}
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0">{rows}</table>
          </td></tr>
        </table>
      </td></tr>

      <tr><td style="padding:0 32px 12px;">
        {_p("What happens next", 20, 28, weight=600, margin="0 0 16px")}
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0">{steps}</table>
      </td></tr>
      {sos}
      <tr><td style="padding:0 32px 32px;">
        {_p(f"Kind regards,<br><strong>{escape(e.sign_off)}</strong>", 16, 24)}
      </td></tr>
    </table>
  </td></tr>

  <tr><td style="padding:24px 8px 0;">
    {_p(f'<strong style="color:{BRAND_DEEP};">GoSafe</strong> &middot; ride safety for GoRide and GoCar', 12, 16, MUTED, margin="0 0 4px")}
    {_p(escape(FOOTER), 12, 16, MUTED)}
    {_p(escape(CONFIDENTIAL), 12, 16, MUTED, margin="4px 0 0") if e.confidential else ""}
  </td></tr>

</table>
</td></tr></table>
</body></html>"""
