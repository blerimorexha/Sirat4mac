# sirat4mac

Kohët e namazit në shiritin lart të Mac-ut (menu bar), me kohën që ka mbetur deri te vakti i ardhshëm.
Kohët merren drejtpërdrejt nga aplikacioni **Sirat** i instaluar në Mac.

Në shirit duket kështu: `Akshami 49 min`

## Çfarë bën

- Shfaq vaktin e ardhshëm dhe kohën e mbetur, p.sh. `Jacia 21 min` ose `Imsaku 9h 38min`.
- Me një klik hapet lista e ditës: Imsaku, Lindja e diellit, Dreka, Ikindia, Akshami dhe Jacia.
  Vakti i ardhshëm del i theksuar, ato që kanë kaluar dalin të zbehta.
- Përdor takvimet që i ka Sirat: Kosovë (BIK, Prishtinë), Shqipëri (KMSH, me qytete),
  Maqedoni e Veriut (me qytete) dhe Mali i Zi (Podgoricë).
- Kohët mund t'i korrigjosh me minuta për qytetin tënd (nga −10 deri në +10).
- Ora verore dhe dimërore llogariten vetë.
- Hapet vetë kur ndizet Mac-u (mund ta çaktivizosh nga lista).
- Nuk lidhet me internet.

## Kërkesat

- Mac me Apple Silicon (M1 ose më i ri) dhe macOS 13 ose më i ri
- Aplikacioni **Sirat – Takvim & Mus'haf** i instaluar nga App Store (në `/Applications`)
- Xcode ose Command Line Tools për ta ndërtuar (`xcode-select --install`)

## Instalimi

```bash
git clone https://github.com/blerimorexha/sirat4mac.git
cd sirat4mac
./build.sh --install
```

Aplikacioni vendoset te `/Applications/sirat4mac.app` dhe shfaqet menjëherë lart në shirit.

Nëse nuk e sheh: shiriti mund të jetë plot, ose ikona mund të jetë pas kamerës (notch).
Mbaj **⌘ Command** dhe tërhiq ikonat për t'i bërë vend.

## Si funksionon

Sirat i mban takvimet brenda aplikacionit si skedarë JSON, në orën standarde të Evropës Qendrore (pa orën verore).
sirat4mac i lexon këta skedarë direkt nga `/Applications/Sirat.app`, ia shton orën verore sipas zonës kohore
të shtetit dhe numëron deri te vakti i ardhshëm. Kur përditësohet Sirat, përditësohen edhe kohët këtu.
Ky projekt nuk përmban asnjë të dhënë nga Sirat.

## Verifikimi

```bash
./scripts/verify-times.sh
```

Krahason çdo ditë të vitit me kalendarin vjetor që ka Sirat (për Prishtinën), përfshirë ndërrimin e orës.

## Shënime

- Për Kosovën, kohët janë për Prishtinën. Nëse në Sirat ke zgjedhur qytet tjetër,
  krahaso një kohë me Sirat dhe vendos ndryshimin te **Korrigjo minutat**.
- Për ta çinstaluar: hiq shenjën te **Hape vetë kur ndizet Mac-u**, kliko **Mbyll sirat4mac**
  dhe fshije `/Applications/sirat4mac.app`.

## Mohim përgjegjësie

Projekt jozyrtar. Nuk është i lidhur me aplikacionin Sirat apo me zhvilluesin e tij.

## English

sirat4mac is a small macOS menu bar app that shows the next Islamic prayer time and the time left until it.
It reads the prayer tables bundled inside the **Sirat** app (installed from the App Store) at runtime,
so it needs Sirat in `/Applications`. Build and install with `./build.sh --install`
(Apple Silicon, macOS 13+, Xcode Command Line Tools). Unofficial; not affiliated with Sirat.

## Licenca

[MIT](LICENSE)
