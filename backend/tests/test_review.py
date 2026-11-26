import json

from app.core import config
from app.services import review
from tests.conftest import needs_emulator

pytestmark = needs_emulator

TRANSCRIPT = [
    {"at": 1.0, "end": 5.1, "text": "Selamat sore Mbak, sesuai aplikasi ya, ke Senayan."},
    {"at": 9.8, "end": 12.8, "text": "Mbak kerja di mana? Udah punya pacar belum? Nomor WA-nya 0812 3456 7890 ya."},
    {"at": 22.0, "end": 25.7, "text": "Cantik banget sih, nanti mampir ke tempat saya dulu."},
]
MARKERS = [
    {"at": 9.8, "kind": "warning", "label": "uncomfortable", "score": 0.65},
    {"at": 22.0, "kind": "high", "label": "sexual_harassment", "score": 0.8},
]


def ride_with_recording(client, login, order="GR-3001"):
    login("rider1")
    client.post("/trips", json={"orderId": order, "riderConsent": True})
    body = {"durationSec": 30.6, "contentType": "audio/mp4", "markers": MARKERS, "transcript": TRANSCRIPT}
    assert client.post(f"/trips/{order}/recording", json=body).status_code == 200
    assert client.post(f"/trips/{order}/recording/done").status_code == 200
    return db_review(order)


def db_review(order):
    from app.core.firebase import db

    return db().document("trips", order).get().to_dict()["recording"].get("review")


def test_without_a_model_the_rules_review_the_whole_ride(client, login, db):
    r = ride_with_recording(client, login)

    assert r["source"] == "rules"
    assert r["label"] == "sexual_harassment"
    assert [m["at"] for m in r["moments"]] == [9.8, 22.0], "each moment cites a transcript line"
    assert "3456" not in r["summary"]


def test_sahabat_ai_reviews_the_masked_transcript(client, login, db, monkeypatch):
    monkeypatch.setattr(config, "LLM_BASE_URL", "http://sahabat.test/v1")
    prompts = []

    def fake_llm(messages, provider):
        prompts.append(messages[-1]["content"])
        return json.dumps({
            "summary": "Pengemudi menanyakan status hubungan lalu mengajak penumpang mampir ke tempatnya.",
            "label": "sexual_harassment",
            "confidence": 0.9,
            "moments": [
                {"at": 9.8, "label": "uncomfortable", "reason": "Pertanyaan pribadi."},
                {"at": 21.7, "label": "sexual_harassment", "reason": "Ajakan mampir."},
            ],
        })

    monkeypatch.setattr(review, "ask_llm", fake_llm)
    r = ride_with_recording(client, login)

    assert (r["source"], r["label"], r["confidence"]) == ("sahabat-ai", "sexual_harassment", 0.9)
    assert [m["at"] for m in r["moments"]] == [9.8, 22.0], "21.7 snaps to the line it cites"
    assert "3456" not in prompts[0] and "[nomor]" in prompts[0], "phone numbers never reach the LLM"


def test_a_broken_llm_answer_falls_back_to_the_rules(client, login, db, monkeypatch):
    monkeypatch.setattr(config, "LLM_BASE_URL", "http://sahabat.test/v1")
    monkeypatch.setattr(review, "ask_llm", lambda messages, provider: "Maaf, saya tidak bisa.")
    r = ride_with_recording(client, login)
    assert r["source"] == "rules"
    assert "sahabat-ai" in r["note"]


def test_gemini_steps_in_when_sahabat_ai_fails(client, login, db, monkeypatch):
    monkeypatch.setattr(config, "LLM_BASE_URL", "http://sahabat.test/v1")
    monkeypatch.setattr(config, "GEMINI_API_KEY", "test-key")

    def fake_llm(messages, provider):
        if provider["source"] == "sahabat-ai":
            raise TimeoutError()
        return json.dumps({"summary": "Ringkasan.", "label": "uncomfortable", "confidence": 0.6, "moments": []})

    monkeypatch.setattr(review, "ask_llm", fake_llm)
    r = ride_with_recording(client, login)
    assert (r["source"], r["model"], r["label"]) == ("gemini", config.GEMINI_MODEL, "uncomfortable")
    assert "sahabat-ai (TimeoutError)" in r["note"]


def test_no_model_connected_says_so(client, login, db):
    r = ride_with_recording(client, login)
    assert r["source"] == "rules" and "No AI model is connected" in r["note"]
