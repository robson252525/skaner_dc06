import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

void main() {
  runApp(const MaterialApp(
    title: "Kontrola DC06",
    home: EkranGlowny(),
    debugShowCheckedModeBanner: false,
  ));
}

class RekordSkanu {
  final String czas;
  final String sciezkaZdjecia;
  final String produkt;
  final String dataWaznosci;
  final String partia;
  final String waga;
  final String wni;
  final String dostawca;
  final bool czyBrakujeWBazie;

  RekordSkanu({
    required this.czas,
    required this.sciezkaZdjecia,
    required this.produkt,
    required this.dataWaznosci,
    required this.partia,
    required this.waga,
    required this.wni,
    required this.dostawca,
    required this.czyBrakujeWBazie,
  });
}

// Globalne listy pamięci – nie resetują się podczas pracy aplikacji
final List<RekordSkanu> _magazynHistorii = [];
final Set<String> _brakujaceNumeryWNI = {};

class EkranGlowny extends StatefulWidget {
  const EkranGlowny({super.key});

  @override
  State<EkranGlowny> createState() => _EkranGlownyState();
}

class _EkranGlownyState extends State<EkranGlowny> {
  int _karta = 0;
  File? _zdjecie;
  bool _skanuje = false;

  String? _wynikProdukt;
  String? _wynikData;
  String? _wynikPartia;
  String? _wynikWaga;
  String? _wynikWni;
  String? _wynikDostawca;
  bool _czyWniNieznany = false;

  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _ocr = TextRecognizer(script: TextRecognitionScript.latin);

  final Map<String, String> _bazaWNI = {
    "22030207": "GOODVALLEY POLSKA (Przechlewo)",
    "28050201": "ANIMEX FOODS (Ełk)",
    "10020202": "ANIMEX FOODS (Kutno K2)",
    "10023801": "ANIMEX FOODS (Kutno K4)",
    "04140316": "SOKOŁÓW S.A. (Osie)",
    "12630215": "SOKOŁÓW S.A. (Tarnów)",
    "14290201": "SOKOŁÓW S.A. (Sokołów Podl.)",
    "30090201": "SOKOŁÓW S.A. (Koło)",
    "14130205": "CEDROB S.A. (Ujazdówek)",
    "14040201": "CEDROB S.A. (Ciechanów)",
    "14020201": "CEDROB S.A. (Niebieskie)",
    "30020202": "DROSED S.A. (Ostrzeszów)",
    "14260203": "DROSED S.A. (Siedlce)",
    "04630201": "PLUKON (Grzmiąca)",
    "14070201": "INDYKPOL (Olsztynek)",
    "28620201": "INDYKPOL (Olsztyn)",
    "30180201": "WIPASZ S.A. (Mława)",
    "14180202": "WIPASZ S.A. (Koło)",
    "14270201": "AGRO-RYDZYNA (Kłoda)",
    "30040201": "SUPERDRIB (Karczew)",
    "14170201": "PINI POLONIA (Kutno)",
  };

  @override
  void dispose() {
    _ocr.close();
    super.dispose();
  }

  Future<void> _wykonajZdjecie(ImageSource source) async {
    final pobranyPlik = await _picker.pickImage(source: source, imageQuality: 95);
    if (pobranyPlik == null) return;

    setState(() {
      _zdjecie = File(pobranyPlik.path);
      _skanuje = true;
    });

    final inputImage = InputImage.fromFilePath(pobranyPlik.path);
    try {
      final ocrText = await _ocr.processImage(inputImage);
      _przetworzTekst(ocrText);
    } catch (_) {}

    final teraz = DateTime.now();
    final czas = "${teraz.hour.toString().padLeft(2, '0')}:${teraz.minute.toString().padLeft(2, '0')}:${teraz.second.toString().padLeft(2, '0')}";

    if (_czyWniNieznany && _wynikWni != null) {
      _brakujaceNumeryWNI.add(_wynikWni!);
    }

    _magazynHistorii.insert(
      0,
      RekordSkanu(
        czas: czas,
        sciezkaZdjecia: pobranyPlik.path,
        produkt: _wynikProdukt ?? "Nieokreślony",
        dataWaznosci: _wynikData ?? "Brak",
        partia: _wynikPartia ?? "Brak",
        waga: _wynikWaga ?? "Brak",
        wni: _wynikWni ?? "Brak stempla",
        dostawca: _wynikDostawca ?? "Nieznany zakład",
        czyBrakujeWBazie: _czyWniNieznany,
      ),
    );

    setState(() {
      _skanuje = false;
    });
  }

  void _przetworzTekst(RecognizedText ocr) {
    List<String> linie = [];
    for (var b in ocr.blocks) {
      for (var l in b.lines) {
        linie.add(l.text.trim());
      }
    }
    String calosc = linie.join("\n").toUpperCase();

    // 1. WETERYNARIA (WNI)
    _wynikWni = null;
    _wynikDostawca = null;
    _czyWniNieznany = false;

    // A. Szukanie bezpośrednio ze słownika
    for (var k in _bazaWNI.keys) {
      if (calosc.replaceAll(RegExp(r'\s+'), '').contains(k)) {
        _wynikWni = k;
        _wynikDostawca = _bazaWNI[k];
        _czyWniNieznany = false;
        break;
      }
    }

    // B. Jeśli nie ma w słowniku, szukamy formatu urzędowego w owalu (PL ... WE / 8 cyfr)
    if (_wynikWni == null) {
      final regOwal = RegExp(r'(?:PL\s*)?(\b\d{8}\b)(?:\s*WE)?');
      final match = regOwal.firstMatch(calosc.replaceAll(" ", ""));
      if (match != null) {
        _wynikWni = match.group(1);
        _wynikDostawca = "DO UZUPEŁNIENIA W BAZIE";
        _czyWniNieznany = true;
      }
    }

    // 2. PRODUKT
    _wynikProdukt = null;
    for (var l in linie) {
      String u = l.toUpperCase();
      if (u.contains("KOTLETY") || u.contains("GULASZ") || u.contains("ROSOŁOWA") || u.contains("ŻEBERKA") || u.contains("SCHAB") || u.contains("KARKÓWKA") || u.contains("FILET")) {
        _wynikProdukt = u;
        break;
      }
    }
    _wynikProdukt ??= (linie.isNotEmpty && linie.first.length > 4 ? linie.first : null);

    // 3. DATA WAŻNOŚCI I NUMER PARTII
    _wynikData = null;
    _wynikPartia = null;

    final regData = RegExp(r'(\b\d{2}[.\-/]\d{2}[.\-/]\d{4}\b)');
    for (int i = 0; i < linie.length; i++) {
      final m = regData.firstMatch(linie[i]);
      if (m != null) {
        _wynikData = m.group(0);
        if (i + 1 < linie.length) {
          String kolejna = linie[i + 1].trim();
          final regPartia = RegExp(r'^[A-Z0-9\-/]{4,15}$');
          if (regPartia.hasMatch(kolejna) && !kolejna.contains("PRZECH") && !kolejna.contains("MASA")) {
            _wynikPartia = kolejna;
          }
        }
        break;
      }
    }

    // 4. MASA NETTO
    _wynikWaga = null;
    final regMasa = RegExp(r'(\d+[.,]?\d*)\s*(KG|G)\b');
    final matchMasa = regMasa.firstMatch(calosc);
    if (matchMasa != null) {
      _wynikWaga = "${matchMasa.group(1)} ${matchMasa.group(2)}";
    }
  }

  void _pokazBrakujaceWNI() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.deepOrange),
            SizedBox(width: 8),
            Text("Brakujące WNI", style: TextStyle(fontSize: 18)),
          ],
        ),
        content: _brakujaceNumeryWNI.isEmpty
            ? const Text("Baza jest kompletna! Wszystkie odczytane dotąd numery WNI są przypisane.")
            : SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: _brakujaceNumeryWNI
                      .map((wni) => ListTile(
                            leading: const Icon(Icons.add_circle_outline, color: Colors.red),
                            title: Text(wni, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            subtitle: const Text("Odczytany stempel – brak zakładu w kodzie"),
                          ))
                      .toList(),
                ),
              ),
        actions: [
          if (_brakujaceNumeryWNI.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() => _brakujaceNumeryWNI.clear());
                Navigator.pop(ctx);
              },
              child: const Text("Wyczyść listę", style: TextStyle(color: Colors.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Zamknij")),
        ],
      ),
    );
  }

  Widget _wierszDanych(String tytul, String? wartosc, {bool wyroznij = false, bool brakWBazie = false}) {
    bool ok = wartosc != null && wartosc.isNotEmpty && wartosc != "Brak";
    Color tlo = ok ? Colors.green.withValues(alpha: 0.12) : Colors.red.withValues(alpha: 0.08);
    Color ramka = ok ? Colors.green.shade600 : Colors.red.shade300;
    Color kolorTekstu = ok ? Colors.green.shade900 : Colors.red.shade800;

    if (brakWBazie) {
      tlo = Colors.orange.withValues(alpha: 0.15);
      ramka = Colors.deepOrange;
      kolorTekstu = Colors.deepOrange.shade900;
    } else if (wyroznij && ok) {
      ramka = Colors.blue.shade700;
      kolorTekstu = Colors.blue.shade900;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: tlo,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ramka, width: (wyroznij || brakWBazie) ? 2.0 : 1.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(tytul, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: brakWBazie ? Colors.deepOrange.shade900 : Colors.black87)),
          Flexible(
            child: Text(
              ok ? wartosc! : "BRAK",
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kolorTekstu),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_karta == 0 ? "Kontrola DC06" : "Historia skanów (${_magazynHistorii.length})"),
        backgroundColor: Colors.orange.shade800,
        actions: [
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.assignment_late_outlined, size: 28),
                if (_brakujaceNumeryWNI.isNotEmpty)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                      child: Text(
                        '${_brakujaceNumeryWNI.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: "Brakujące WNI do dodania",
            onPressed: _pokazBrakujaceWNI,
          ),
          if (_karta == 1 && _magazynHistorii.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_forever),
              tooltip: "Wyczyść historię",
              onPressed: () => setState(() => _magazynHistorii.clear()),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _karta,
        selectedItemColor: Colors.orange.shade900,
        onTap: (i) => setState(() => _karta = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: "Skanuj"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "Historia"),
        ],
      ),
      body: _karta == 0 ? _budujSkaner() : _budujHistorie(),
    );
  }

  Widget _budujSkaner() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _skanuje ? null : () => _wykonajZdjecie(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt, color: Colors.white),
                  label: const Text("Aparat", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _skanuje ? null : () => _wykonajZdjecie(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library, color: Colors.white),
                  label: const Text("Z galerii", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_skanuje)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          if (_zdjecie != null && !_skanuje) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(_zdjecie!, height: 160, width: double.infinity, fit: BoxFit.cover),
            ),
            const SizedBox(height: 8),
            _wierszDanych("WETERYNARYJNY (WNI)", _wynikWni, wyroznij: !_czyWniNieznany, brakWBazie: _czyWniNieznany),
            _wierszDanych("Dostawca / Zakład", _wynikDostawca, brakWBazie: _czyWniNieznany),
            _wierszDanych("Produkt", _wynikProdukt),
            _wierszDanych("Termin ważności", _wynikData),
            _wierszDanych("Numer partii", _wynikPartia),
            _wierszDanych("Masa netto", _wynikWaga),
          ],
        ],
      ),
    );
  }

  Widget _budujHistorie() {
    if (_magazynHistorii.isEmpty) {
      return const Center(child: Text("Brak zapisanych skanów w historii."));
    }
    return ListView.builder(
      itemCount: _magazynHistorii.length,
      itemBuilder: (ctx, i) {
        final r = _magazynHistorii[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: r.czyBrakujeWBazie ? const BorderSide(color: Colors.deepOrange, width: 1.5) : BorderSide.none,
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(File(r.sciezkaZdjecia), width: 75, height: 75, fit: BoxFit.cover),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("WNI: ${r.wni}", style: TextStyle(fontWeight: FontWeight.bold, color: r.czyBrakujeWBazie ? Colors.deepOrange : Colors.blue)),
                          Text(r.czas, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                      Text(
                        r.dostawca,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: r.czyBrakujeWBazie ? Colors.deepOrange.shade800 : Colors.black87,
                        ),
                      ),
                      Text("${r.produkt} | ${r.waga}", style: const TextStyle(fontSize: 12)),
                      Text("Data: ${r.dataWaznosci} | Partia: ${r.partia}", style: const TextStyle(fontSize: 11, color: Colors.black54)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
