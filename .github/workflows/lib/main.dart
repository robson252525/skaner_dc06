import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

void main() {
  runApp(const MaterialApp(
    title: "Skaner DC06",
    home: GlownyEkranAplikacji(),
    debugShowCheckedModeBanner: false,
  ));
}

class WpisHistorii {
  final String czas;
  final String sciezkaZdjecia;
  final String? produkt;
  final String? dataWaznosci;
  final String? partia;
  final String? waga;
  final String? wni;
  final String? dostawca;
  final String? ean;
  final String surowyTekst;

  WpisHistorii({
    required this.czas,
    required this.sciezkaZdjecia,
    this.produkt,
    this.dataWaznosci,
    this.partia,
    this.waga,
    this.wni,
    this.dostawca,
    this.ean,
    required this.surowyTekst,
  });
}

class GlownyEkranAplikacji extends StatefulWidget {
  const GlownyEkranAplikacji({super.key});

  @override
  State<GlownyEkranAplikacji> createState() => _GlownyEkranAplikacjiState();
}

class _GlownyEkranAplikacjiState extends State<GlownyEkranAplikacji> {
  int _aktualnaZakladka = 0;
  final List<WpisHistorii> _listaHistorii = [];

  File? _biezaceZdjecie;
  bool _trwaPrzetwarzanie = false;

  String? _produkt;
  String? _dataWaznosci;
  String? _numerPartii;
  String? _masaNetto;
  String? _kodWNI;
  String? _nazwaDostawcy;
  String? _kodEAN;
  String _odczytanyTekstRaw = "";

  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final BarcodeScanner _barcodeScanner = BarcodeScanner();

  final Map<String, String> _bazaWNI = {
    "22030207": "GOODVALLEY POLSKA (Przechlewo)",
    "28050201": "ANIMEX FOODS (Ełk)",
    "10020202": "ANIMEX FOODS (Kutno K2)",
    "10023801": "ANIMEX FOODS (Kutno K4)",
    "04140316": "SOKOŁÓW S.A. (Osie)",
    "12630215": "SOKOŁÓW S.A. (Tarnów)",
    "14290201": "SOKOŁÓW S.A. (Sokołów Podlaski)",
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
    _textRecognizer.close();
    _barcodeScanner.close();
    super.dispose();
  }

  Future<void> _wykonajSkan(ImageSource zrodlo) async {
    final XFile? pobranyPlik = await _picker.pickImage(source: zrodlo, imageQuality: 95);
    if (pobranyPlik == null) return;

    setState(() {
      _biezaceZdjecie = File(pobranyPlik.path);
      _trwaPrzetwarzanie = true;
      _resetujOdczyty();
    });

    final inputImage = InputImage.fromFilePath(pobranyPlik.path);

    // 1. Kody kreskowe (EAN)
    try {
      final kody = await _barcodeScanner.processImage(inputImage);
      if (kody.isNotEmpty) {
        _kodEAN = kody.first.rawValue;
      }
    } catch (_) {}

    // 2. Rozpoznawanie tekstu OCR
    try {
      final rozpoznany = await _textRecognizer.processImage(inputImage);
      _odczytanyTekstRaw = rozpoznany.text;
      _analizujEtykiete(rozpoznany);
    } catch (_) {}

    // 3. Dodanie do historii ze zdjęciem
    final now = DateTime.now();
    final godzina = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

    _listaHistorii.insert(
      0,
      WpisHistorii(
        czas: godzina,
        sciezkaZdjecia: pobranyPlik.path,
        produkt: _produkt,
        dataWaznosci: _dataWaznosci,
        partia: _numerPartii,
        waga: _masaNetto,
        wni: _kodWNI,
        dostawca: _nazwaDostawcy,
        ean: _kodEAN,
        surowyTekst: _odczytanyTekstRaw,
      ),
    );

    setState(() {
      _trwaPrzetwarzanie = false;
    });
  }

  void _resetujOdczyty() {
    _produkt = null;
    _dataWaznosci = null;
    _numerPartii = null;
    _masaNetto = null;
    _kodWNI = null;
    _nazwaDostawcy = null;
    _kodEAN = null;
    _odczytanyTekstRaw = "";
  }

  void _analizujEtykiete(RecognizedText doc) {
    List<String> wiersze = [];
    for (var b in doc.blocks) {
      for (var l in b.lines) {
        wiersze.add(l.text.trim());
      }
    }

    String calyTekstUpper = wiersze.join("\n").toUpperCase();

    // Produkt
    if (calyTekstUpper.contains("KOTLETY")) {
      _produkt = "MIĘSO NA KOTLETY Z INDYKA";
    } else if (calyTekstUpper.contains("GULASZ")) {
      _produkt = "MIĘSO NA GULASZ Z SZYNKI";
    } else if (calyTekstUpper.contains("ROSOŁOWA")) {
      _produkt = "PORCJA ROSOŁOWA WOŁOWA";
    } else if (calyTekstUpper.contains("ŻEBERKA") || calyTekstUpper.contains("ZEBERKA")) {
      _produkt = "ŻEBERKA WIEPRZOWE";
    }

    // WNI - szukanie z bazy oraz szukanie owalu (np. PL 22030207 WE)
    for (var kod in _bazaWNI.keys) {
      if (calyTekstUpper.replaceAll(RegExp(r'\s+'), '').contains(kod)) {
        _kodWNI = kod;
        _nazwaDostawcy = _bazaWNI[kod];
        break;
      }
    }
    if (_kodWNI == null) {
      final regOwal = RegExp(r'(?:PL\s*)?(\d{8})(?:\s*WE)?');
      final matchOwal = regOwal.firstMatch(calyTekstUpper.replaceAll(" ", ""));
      if (matchOwal != null && matchOwal.group(1) != _kodEAN) {
        _kodWNI = matchOwal.group(1);
        _nazwaDostawcy = _bazaWNI[_kodWNI] ?? "Nieznany zakład (poza listą)";
      }
    }

    // Data ważności (DD-MM-YYYY lub DD.MM.YYYY lub DD/MM/YYYY)
    final regData = RegExp(r'(\b\d{2}[.\-/]\d{2}[.\-/]\d{4}\b)');
    for (int i = 0; i < wiersze.length; i++) {
      final match = regData.firstMatch(wiersze[i]);
      if (match != null) {
        _dataWaznosci = match.group(0);

        // Numer partii: na tackach zawsze w następnej linii pod datą
        if (i + 1 < wiersze.length) {
          String nastepna = wiersze[i + 1].trim();
          // Partia to ciąg cyfr/znaków (np. 626400021 albo 2660410), ignorujemy wyrazy instrukcji
          final regPartiaLinia = RegExp(r'^[A-Z0-9\-/]{4,15}$');
          if (regPartiaLinia.hasMatch(nastepna) && !nastepna.contains("PRZECH") && !nastepna.contains("MASA")) {
            _numerPartii = nastepna;
          }
        }
        break;
      }
    }

    // Jeśli partia nie była pod datą, szukamy linii zawierającej etykietę partii
    if (_numerPartii == null) {
      for (int i = 0; i < wiersze.length; i++) {
        String w = wiersze[i].toUpperCase();
        if (w.contains("NUMER PARTII") || w.contains("NR PARTII") || w.contains("LOT")) {
          // sprawdź w tej samej linii
          final regW = RegExp(r'(\d{6,14})');
          final mW = regW.firstMatch(w);
          if (mW != null) {
            _numerPartii = mW.group(1);
          } else if (i + 1 < wiersze.length) {
            // sprawdź linię niżej
            final regN = RegExp(r'^[A-Z0-9\-/]{4,15}$');
            if (regN.hasMatch(wiersze[i + 1].trim())) {
              _numerPartii = wiersze[i + 1].trim();
            }
          }
          break;
        }
      }
    }

    // Masa netto (np. 500 g, 500g e, 0,463 kg, 0.335 kg)
    final regMasa = RegExp(r'(\d+[.,]?\d*)\s*(KG|G)\b');
    final matchMasa = regMasa.firstMatch(calyTekstUpper);
    if (matchMasa != null) {
      _masaNetto = "${matchMasa.group(1)} ${matchMasa.group(2)}";
    }
  }

  Widget _kafelekDanych(String tytul, String? wartosc, String komunikatBledu) {
    final bool jestOk = wartosc != null && wartosc.isNotEmpty;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: jestOk ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: jestOk ? Colors.green.shade600 : Colors.red.shade400, width: 1.2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(tytul, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.black87)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              jestOk ? wartosc! : komunikatBledu,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: jestOk ? Colors.green.shade900 : Colors.red.shade800,
              ),
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
        title: Text(_aktualnaZakladka == 0 ? "Kontrola Etykiet DC06" : "Historia Kontroli (${_listaHistorii.length})"),
        backgroundColor: Colors.orange.shade800,
        actions: [
          if (_aktualnaZakladka == 0 && _odczytanyTekstRaw.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.text_snippet),
              tooltip: "Podgląd surowego tekstu OCR",
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Odczytany surowy tekst"),
                    content: SingleChildScrollView(child: Text(_odczytanyTekstRaw)),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Zamknij"))],
                  ),
                );
              },
            ),
          if (_aktualnaZakladka == 1 && _listaHistorii.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_forever),
              tooltip: "Wyczyść całą historię",
              onPressed: () {
                setState(() {
                  _listaHistorii.clear();
                });
              },
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _aktualnaZakladka,
        selectedItemColor: Colors.orange.shade900,
        onTap: (index) => setState(() => _aktualnaZakladka = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: "Skaner"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "Historia"),
        ],
      ),
      body: _aktualnaZakladka == 0 ? _widokSkanera() : _widokHistorii(),
    );
  }

  Widget _widokSkanera() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _trwaPrzetwarzanie ? null : () => _wykonajSkan(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt, color: Colors.white),
                  label: const Text("Aparat", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _trwaPrzetwarzanie ? null : () => _wykonajSkan(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library, color: Colors.white),
                  label: const Text("Z galerii", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey.shade700, padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_trwaPrzetwarzanie)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          if (_biezaceZdjecie != null && !_trwaPrzetwarzanie) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(_biezaceZdjecie!, height: 160, width: double.infinity, fit: BoxFit.cover),
            ),
            const SizedBox(height: 12),
            _kafelekDanych("Produkt", _produkt, "NIE ROZPOZNANO"),
            _kafelekDanych("Termin ważności", _dataWaznosci, "BRAK DATY"),
            _kafelekDanych("Numer partii", _numerPartii, "BRAK PARTII"),
            _kafelekDanych("Masa netto", _masaNetto, "BRAK WAGI"),
            _kafelekDanych("Stempel WNI", _kodWNI, "BRAK (SPRAWDŹ SPÓD TACKI)"),
            _kafelekDanych("Dostawca", _nazwaDostawcy, "BRAK W BAZIE"),
            _kafelekDanych("Kod EAN", _kodEAN, "BRAK KODU (SPRAWDŹ SPÓD TACKI)"),
          ],
        ],
      ),
    );
  }

  Widget _widokHistorii() {
    if (_listaHistorii.isEmpty) {
      return const Center(child: Text("Brak zapisanych skanów w historii."));
    }
    return ListView.builder(
      itemCount: _listaHistorii.length,
      itemBuilder: (context, i) {
        final w = _listaHistorii[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: InkWell(
            onTap: () {
              // Powiększenie zdjęcia po kliknięciu w historii
              showDialog(
                context: context,
                builder: (ctx) => Dialog(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.file(File(w.sciezkaZdjecia)),
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Zamknij")),
                    ],
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      File(w.sciezkaZdjecia),
                      width: 75,
                      height: 75,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(w.czas, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 12)),
                            Text(w.waga ?? "--", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(w.produkt ?? "Produkt nieznany", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text("Data: ${w.dataWaznosci ?? '--'} | Partia: ${w.partia ?? '--'}", style: const TextStyle(fontSize: 12)),
                        Text("Dostawca: ${w.dostawca ?? w.wni ?? '--'}", style: const TextStyle(fontSize: 11, color: Colors.black54)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
