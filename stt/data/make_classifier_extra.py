"""Extra training sentences for the 5-label classifier, aimed at what the synthetic set lacks.

The synthetic set (one LLM generator) has almost no harmless look-alikes, friendly swearing, trip complaints,
slang threats or ordinary insults, and the eval showed exactly those failing. These are written by a different
author (Claude, 2026-11-27) and deliberately NOT copied from eval/ride_script.csv, so the eval stays a test.

Each base sentence also gets a speech-to-text style copy (lower case, no punctuation), because the classifier
reads Whisper output. Writes classifier_extra.csv next to this file. Labels: normal | uncomfortable | sexual |
threat | victim (see eval/train_classifier.py).
"""

import csv
import random
import re
from pathlib import Path

A = ["Pak", "Bang", "Mas", "Kak", "Mbak", "Om", "Neng", "Bro"]

DATA = {
    # --- normal: everyday ride talk, code-mixed ---
    ("normal", "smalltalk"): [
        "{a}, AC-nya boleh dikecilin dikit gak?", "Udah lama narik, {a}?", "Hari ini rame ya orderan?",
        "{a}, nanti mampir indomaret bentar boleh? Mau beli minum.", "Saya turun pas di depan pos satpam aja.",
        "Wah ujannya deres banget, untung pake jas hujan.", "{a}, ini lewat Kemang atau Tendean?",
        "Gue lagi WFO hari ini, biasanya WFH sih.", "Lagunya enak {a}, ini lagu apa ya?",
        "Maaf {a}, saya angkat telepon bentar ya.", "Btw {a}, helmnya ada yang lebih kecil gak?",
        "Duh lupa bawa payung, nanti turunnya pas di kanopi aja.", "Tadi meeting-nya di-reschedule, jadi santai.",
        "{a}, bisa pelan dikit? Saya bawa kue.", "Ini udah deket kok, belokan kedua kiri.",
        "Kok sepi ya jalanan hari ini, libur kali ya.", "Literally baru pulang dari bandara, capek banget.",
        "Nanti saya bayar pakai GoPay ya {a}.", "{a} asli orang mana? Logatnya kayak Medan.",
        "Gue mau ke kampus, ada kelas jam sepuluh.", "Maaf ya {a} nunggu lama, tadi lift-nya penuh.",
        "Wah enak ya {a} kalau malem udah gak macet.", "Nanti tolong berhentiin di depan apotek ya.",
        "Sinyal di sini jelek banget, maps-nya muter terus.", "Makasih ya {a}, nyetirnya enak.",
    ],
    ("normal", "complaint"): [
        "{a}, kok lewat sini? Di maps harusnya lurus.", "Ini tarifnya kok beda sama yang di aplikasi?",
        "Duh telat deh gue, macetnya parah banget.", "{a}, jangan ngebut dong, saya takut jatuh.",
        "Kenapa muter balik {a}? Tadi kan udah bener jalannya.", "Ordernya kok lama banget sih nyampenya?",
        "{a}, helmnya bau banget, gak pernah dicuci ya?", "Ih kok berhenti di sini, saya bilang di lobby.",
        "Kok AC-nya gak dingin sih {a}?", "Gue udah nunggu dua puluh menit lho tadi.",
        "{a}, tolong rem-nya jangan mendadak gitu.", "Harusnya gak lewat tol, kan saya gak minta.",
        "Ini argonya kemahalan deh kayaknya.", "Kok dari tadi muter-muter gak nyampe-nyampe sih.",
        "{a} bisa gak sih nyalain lampu sein dulu?",
    ],
    ("normal", "friendly_swear"): [
        "Anjir, macetnya gak ada obat.", "Anjay {a}, motornya kenceng juga.", "Gila sih panas banget hari ini.",
        "Bangsat, gue lupa matiin kompor kayaknya.", "Shit, dompet gue ketinggalan di kantor.",
        "Damn, hujannya makin deres.", "Anjing, tadi kucing nyebrang tiba-tiba.", "Sialan, HP gue mati lagi.",
        "Fuck, gue salah kirim email ke bos.", "Gila tuh mobil, nyalip seenaknya.", "Kampret, sendal gue putus.",
        "Ya ampun, setan banget deadline minggu ini.", "Anjir lucu banget videonya, {a} udah liat belum?",
        "Bego banget gue, kartu akses ketinggalan.", "Tai, kebasahan semua nih tas gue.",
        "Brengsek emang tuh ojol yang nyerobot tadi.", "Goblok banget sih gue, salah naro alamat.",
        "Shit, ternyata meetingnya udah mulai.", "Anjrit, mahal banget parkirnya.",
        "Asu, aku lali nggawa charger.",
    ],
    ("normal", "look_alike"): [
        "Gue tau warung soto enak deket sini, mau gue kasih tau?", "Awas {a}, ada lubang di depan.",
        "Hati-hati {a}, aspalnya licin habis ujan.", "Kucing saya baru lahiran, anaknya lucu banget.",
        "Anaknya kehujanan, nanti saya ganti bajunya di rumah.", "Baju kerjanya saya buka di kantor aja nanti.",
        "Istri saya cantik banget pas nikahan kemarin.", "Ponakan gue cantik banget, mirip artis.",
        "Pacar saya juga orang Bandung.", "Nomor rumahnya tiga puluh, yang catnya biru.",
        "Nanti saya kirim nomor pesanan ke customer service.", "Hotelnya yang deket stasiun ya {a}.",
        "Mau check-in hotel dulu, ada acara kantor.", "Tolong {a}, ambil jalur kiri aja.",
        "Tolong tungguin bentar ya {a}, saya ambil barang.", "Diam-diam ternyata dia udah nikah lho.",
        "Diam aja di lobby, nanti temen saya turun.", "Saya tahu jalan pintasnya, lewat gang sebelah.",
        "Saya tau rumah sakit terdekat, belok kanan.", "Bunuh waktu sambil main game aja.",
        "Hajar aja {a}, mumpung jalannya kosong.", "Sendirian aja nih ke kantornya hari ini, temen cuti.",
        "Sayangnya tokonya udah tutup.", "Mampir ke tempat saya dulu ya, ambil berkas, cuma lima menit.",
        "Pegang helmnya dulu ya {a}, saya mau ikat rambut.", "Daging babinya jangan dicampur sama yang lain.",
        "Anjing tetangga gue galak banget.", "Pisau dapurnya ketinggalan di rumah ibu.",
        "Saya pukul empat harus udah sampai.", "Tinggal sendiri di kos itu enak, bebas.",
        "Nomor WA kantor ada di website kok.", "Seksi konsumsi acaranya belum dateng.",
        "Pacarnya temen gue kerja di Gojek juga.", "Awas kamu kepleset, lantainya basah.",
        "Jangan lapor dulu ke bos, nanti gue yang jelasin.",
    ],
    # --- uncomfortable: directed insults and pushy personal questions, slang ---
    ("uncomfortable", "insult"): [
        "Goblok lu, nyetir aja gak becus.", "Dasar tolol, udah dibilang belok kiri!", "Bego banget sih lo.",
        "Lu bisa mikir gak sih? Dasar idiot.", "Bacot lu, diem aja nyetir.", "Dasar cewek bego, gak tau jalan.",
        "Anjing lu, lama banget.", "Bangsat lu, gue telat gara-gara lu.", "Mulut lu kayak sampah ya.",
        "Dasar sopir kampungan.", "Lu tuh gak guna banget sih.", "Otak lu ditaruh di mana sih?",
        "Penumpang kayak lu gak usah naik ojol.", "Najis gue boncengin orang kayak lu.",
        "Dasar miskin, bayar ojol aja ngutang.",
    ],
    ("uncomfortable", "probing"): [
        "{a} udah nikah belum? Kok cantik masih sendiri.", "Kosnya sendirian ya? Ada yang jaga gak?",
        "Pulang kerja jam berapa biasanya? Biar bisa saya jemput.", "Rumahnya yang mana sih, yang pagar hijau itu?",
        "Boleh minta IG-nya gak? Biar bisa ngobrol.", "Save nomor saya ya, nanti chat aja langsung.",
        "Umurnya berapa sih? Masih kuliah ya?", "Orang tuanya tinggal bareng gak?",
        "Besok order saya lagi ya, gak usah lewat aplikasi.", "Cowoknya gak marah kalau naik ojol malem-malem?",
    ],
    # --- sexual: slang ---
    ("sexual", "sexual"): [
        "Badan lu bagus juga ya.", "Bajunya ketat banget sih, sengaja ya?", "Boleh pegang tangannya gak?",
        "Duduknya maju dong, biar nempel.", "Pahanya mulus banget.", "Mau gak nginep di kos gue malam ini?",
        "Kamu seksi banget kalau pakai rok gitu.", "Cium dulu dong sebelum turun.", "Lu pasti enak dipeluk.",
        "Gue bayarin deh asal mau nemenin gue malem ini.", "Kirimin foto lu dong, yang seksi.",
        "Pegangan ke pinggang gue aja, gak usah malu.", "Jalan-jalan ke hotel yuk habis ini.",
        "Cantik-cantik gini pasti udah sering ya.", "Bodi lu bikin gue gak fokus nyetir.",
    ],
    # --- threat: slang threats, weapons, coercion ---
    ("threat", "threat"): [
        "Diem lu, atau gue turunin di sini.", "Jangan teriak, gue punya pisau.", "Gue tau kos lu, jangan macem-macem.",
        "Kalau lu lapor, gue cari lu.", "Gue hajar lu kalau gak nurut.", "Turutin aja kalau mau selamat.",
        "Jangan bikin gue emosi, gue bisa nekat.", "HP lu siniin sekarang.", "Gue bawa senjata, jangan coba-coba.",
        "Lu gak bakal bisa ke mana-mana.", "Kita gak ke tujuan lu, ikut gue dulu.", "Sekali lagi lu ngomong, gue tampar.",
        "Gue matiin lu kalau berani kabur.", "Dompet lu kasih ke gue, cepet.", "Jangan sampai gue liat lu lapor polisi.",
        "Awas lu ya, gue inget muka lu.", "Diem atau gue bikin lu nyesel.", "Gue tungguin lu di depan rumah besok.",
        "Gak usah banyak bacot, ikutin perintah gue.", "Kalau gue kasih bintang satu, lu mau apa? Gue habisin lu.",
    ],
    # --- victim: refusal and distress from the person being harmed ---
    ("victim", "victim"): [
        "Pak, saya gak nyaman ya ditanya-tanya gitu.", "Tolong jangan pegang-pegang saya.",
        "Berhenti di sini aja, saya mau turun.", "Saya mau turun sekarang juga, tolong berhenti.",
        "Jangan ngomong gitu lagi, saya laporin.", "Tolong! Tolong, ada yang bisa bantu?",
        "Pak, ini bukan arah rumah saya, saya mau turun.", "Lepasin tangan saya!",
        "Saya udah bilang gak mau, jangan maksa.", "Tolong anterin saya ke tempat rame aja.",
        "Saya takut, tolong jangan lewat jalan sepi.", "Mas, berhentiin motornya sekarang!",
        "Jangan sentuh saya!", "Udah cukup, saya gak mau denger lagi.", "Saya teriak nih kalau gak berhenti.",
    ],
}


def asr_style(text: str) -> str:
    """What Whisper writes: lower case, no punctuation."""
    return re.sub(r"\s+", " ", re.sub(r"[^\w\s-]", " ", text.lower())).strip()


def main() -> None:
    random.seed(11)
    rows = []
    for (label, kind), lines in DATA.items():
        for line in lines:
            text = line.replace("{a}", random.choice(A)) if "{a}" in line else line
            rows.append((text, label, kind))
            rows.append((asr_style(text), label, kind))
    out = Path(__file__).with_name("classifier_extra.csv")
    with out.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["text", "label5", "kind", "source"])
        w.writerows((t, l, k, "claude-2026-11-27") for t, l, k in rows)
    print(f"{len(rows)} rows -> {out}")


if __name__ == "__main__":
    main()
