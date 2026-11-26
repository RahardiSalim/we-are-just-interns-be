# GoSafe eval recording script

Read these aloud and record them, to measure the whole pipeline (speech-to-text, classifier, rules) on real voices. The labels live in [`ride_script.csv`](ride_script.csv): `label` is the truth (normal, uncomfortable, sexual_harassment, threat), `expect` is what the app **should** do (none, warning, high, sos, no_text). It's the target, not today's behaviour, so false alarms show up too.

## How to record

- **One file per scenario**, reading its lines in order with a normal 1 to 2 second pause between lines, as in a real conversation. Don't read the IDs.
- **Two people is best** (one driver, one passenger). One person can read both roles.
- **Speak naturally.** Slang, fillers ("eh", "hmm"), and small changes to the words are fine, even good. Note big changes in the log.
- **Record each scenario in up to three settings**, if you can:
  - `quiet`: a quiet room, phone on the table.
  - `street`: outside or near traffic, phone in hand.
  - `pocket`: phone in a jacket or trouser pocket (closest to a motorbike ride).
- **Format:** WAV or M4A, any sample rate (the eval converts to 16 kHz mono). A phone voice recorder app is fine.
- **File name:** `<scenario>_<setting>_<initials>.<ext>`, e.g. `D_harassment_street_rs.m4a`.
- **Where:** `stt/eval/recordings/`. Never commit audio: `stt/.gitignore` ignores it, and it's people's voices.
- **Consent:** everyone whose voice is recorded agrees, and knows it's for testing only. Don't use real names, addresses or phone numbers.
- **Safe phrase (G):** G01 and G02 use the default phrase. If you've set your own in the app, add a line with it and note it.
- **Language:** mostly Indonesian with some English, as written. The swear words and insults are deliberate: the system has to tell friendly swearing (B) from swearing *at* someone (C, F).

## Log

Keep a short line per file in `recordings/log.md`: file, setting, speakers, anything unusual (a line skipped, a car horn over E03).

## Script


### A. Normal ride (code-mixed, should trigger nothing)

- **A01** _driver:_ Halo kak, sesuai aplikasi ya, ke Kuningan City?
- **A02** _passenger:_ Iya bang, btw boleh lewat Casablanca aja, soalnya Sudirman macet parah.
- **A03** _driver:_ Siap kak. Lagi buru-buru ya?
- **A04** _passenger:_ Iya nih, ada meeting jam tiga, literally udah telat.
- **A05** _driver:_ Aman kak, saya cari jalan tikus deh.
- **A06** _passenger:_ Thanks bang, sorry ya jadi ngerepotin.
- **A07** _driver:_ Santai aja kak. Helmnya udah pas belum?
- **A08** _passenger:_ Udah kok. Eh bang, nanti berhenti di lobby depan aja ya.
- **A09** _driver:_ Oke, udah sampai ya kak. Jangan lupa bintang limanya, hehe.
- **A10** _passenger:_ Pasti bang, makasih banyak, hati-hati di jalan.

### B. Friendly swearing, not at anyone (should trigger nothing)

- **B01** _passenger:_ Anjir macet banget, gila sih ini jam pulang kantor.
- **B02** _driver:_ Iya kak, emang anjing nih jalanan kalau jam segini.
- **B03** _passenger:_ Asli, tadi bos gue juga bangsat banget, kerjaan numpuk.
- **B04** _driver:_ Wah sabar kak, emang kadang kerjaan bikin stres.
- **B05** _passenger:_ Shit, HP gue lowbat. Bang, ada charger gak?
- **B06** _driver:_ Ada kak, colok aja di belakang.
- **B07** _passenger:_ Fuck, laptop gue ketinggalan. Udah lah, gapapa, lanjut aja.

### C. Argument that turns into insults (warning at C05)

- **C01** _passenger:_ Pak, kok muter-muter sih? Ini bukan jalan yang di aplikasi.
- **C02** _driver:_ Ini lebih cepat kak, percaya aja sama saya.
- **C03** _passenger:_ Lebih cepat apanya, argonya jadi mahal gini!
- **C04** _driver:_ Kakak jangan ngegas dong, saya udah capek seharian.
- **C05** _passenger:_ Goblok banget sih lu, bisa nyetir gak?  ⚠️ warning
- **C06** _driver:_ Heh, jaga mulut lu ya, dasar cewek tolol.  ⚠️ warning
- **C07** _passenger:_ Udah, saya turun di sini aja. Nanti saya lapor.

### D. Harassment that escalates (warning at D03, high at D06)

- **D01** _driver:_ Kak, kerja di mana? Kok pulangnya malam terus?
- **D02** _passenger:_ Di kantor aja pak. Fokus nyetir aja ya.
- **D03** _driver:_ Udah punya pacar belum? Tinggal sendirian ya di kos?  ⚠️ warning
- **D04** _passenger:_ Pak, itu bukan urusan bapak.
- **D05** _driver:_ Minta nomor WA-nya dong kak, biar bisa jemput lagi besok.  ⚠️ warning
- **D06** _driver:_ Cantik banget sih kamu, badannya juga seksi.  🔴 high
- **D07** _driver:_ Mampir dulu yuk ke tempat saya, gak jauh kok.  🔴 high
- **D08** _passenger:_ Pak, berhenti di sini aja. Saya mau turun sekarang.

### E. Threat and intimidation (high at E03)

- **E01** _driver:_ Kak, jangan banyak tanya ya, ikutin aja.  ⚠️ warning
- **E02** _passenger:_ Pak, kok belok ke sini? Ini bukan arahnya.
- **E03** _driver:_ Diam aja, saya tahu rumah kamu di mana.  🔴 high
- **E04** _driver:_ Awas kamu kalau berani lapor-lapor.  🔴 high
- **E05** _passenger:_ Tolong pak, berhenti! Tolong!  🔴 high
- **E06** _driver:_ Lu mau gue habisin? Shut up, diem!  🔴 high

### F. Passenger threatens the driver (record on the driver's phone)

- **F01** _passenger:_ Bang, lu jangan macem-macem ya, gue bawa pisau.  🔴 high
- **F02** _passenger:_ Cepetan, kalau telat gue hajar lu.  🔴 high
- **F03** _driver:_ Mas, tolong jangan kasar, saya cuma nganter.
- **F04** _passenger:_ Bacot! Dasar sopir miskin, bajingan.  ⚠️ warning

### G. Safe phrase and near misses (SOS only at G01 and G02)

- **G01** _passenger:_ Pak, nanti lewat jalan biasa aja ya.  🆘 SOS
- **G02** _passenger:_ Oh iya Pak, nanti lewat jalan biasa aja ya, saya buru-buru.  🆘 SOS
- **G03** _passenger:_ Pak, lewat jalan tol aja ya biar cepet.
- **G04** _passenger:_ Jalan biasa macet gak sih Pak?
- **G05** _passenger:_ Iya pak, lewat jalan biasa aja nggak apa-apa.

### H. Look-alikes: danger words in harmless sentences (should trigger nothing)

- **H01** _passenger:_ Pak, tolong belok kiri di depan ya.
- **H02** _passenger:_ Anak saya basah kena hujan, nanti saya buka bajunya di rumah.
- **H03** _driver:_ Saya tahu rumah makan padang yang enak di sini.
- **H04** _driver:_ Awas kamu jatuh kak, jalannya licin.
- **H05** _passenger:_ Sayangnya hujan ya, padahal mau jogging.
- **H06** _passenger:_ Pacar saya juga kerja di Sudirman.
- **H07** _passenger:_ Nomor rumahnya dua belas, yang pagar hitam.
- **H08** _passenger:_ Hotelnya di sebelah kanan ya Pak, yang ada lobby-nya.
- **H09** _passenger:_ Anjingnya tetangga saya lucu banget.
- **H10** _driver:_ Wah adik saya cantik banget pas wisuda kemarin.
- **H11** _passenger:_ Bunuh waktu aja lah, main HP sambil nunggu.

### I. No speech (Whisper should write nothing)

- **I01** (30 detik diam: jangan bicara)
- **I02** (30 detik suara jalan atau motor: jangan bicara)
- **I03** (30 detik musik atau radio: jangan bicara)

## Why these lines

- **A, B and H** measure **false alarms**: ordinary talk, friendly swearing, and danger words in harmless sentences ("saya tahu rumah makan", "awas kamu jatuh", "tolong belok kiri", "anjingnya lucu").
- **C to F** measure **recall**: insults, escalating harassment and threats, from both rider and driver.
- **G** checks the safe phrase fires on the real thing and not on similar sentences (G05 is from Akmal's own script).
- **I** measures **Whisper hallucinations**: any text from silence, noise or music is invented.
