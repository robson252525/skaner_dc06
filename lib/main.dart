import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

void main() {
  runApp(const MaterialApp(
    title: "Skaner DC06",
    home: EkranAplikacji(),
    debugShowCheckedModeBanner: false,
  ));
}

class RaportHistorii {
  final String czas;
  final String sciezkaPliku;
  final String? produkt;
  final String? data;
  final String? partia;
  final String? waga;
  final String? wni;
  final String? dostawca;
  final String? ean;

  RaportHistorii({
    required this.czas,
    required this.sciezkaPliku,
    this.produkt,
    this.data,
    this.partia,
    this.waga,
    this.wni,
    this.dostawca,
    this.ean,
  });
}

class EkranAplikacji extends StatefulWidget {
  const EkranAplikacji({super.key});

  @override
  State<EkranAplikacji> createState() => _EkranAplikacjiState();
}

class _EkranAplikacjiState extends State<EkranAplikacji> {
  int _indeksZakladki = 0;
  final List<RaportHistorii> _historia = [];

  File? _zdjecie;
  bool _laduje = false;

  String? produkt;
  String? dataWaznosci;
  String? numerPartii;
  String? masaNetto;
  String? kodWNI;
  String? nazwaDostawcy;
  String? kodEAN;

  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final BarcodeScanner _barcodeScanner = BarcodeScanner();

  final Map<String, String> bazaWNI = {
    "22030207": "GOODVALLEY (Przechlewo)",
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
    _textRecognizer.close();
    _barcodeScanner.close();
    super.dispose();
  }

  Future<void> _zrobSkan(ImageSource zrodlo) async {
    final XFile? plik = await _picker.pickImage(source: zrodlo, imageQuality: 95);
    if (plik == null) return;

    setState(() {
      _zdjecie = File(plik.path);
      _laduje = true;
      _resetujDane();
    });

    final inputImage = InputImage.fromFilePath(plik.path);

    try {
      final kody = await _barcodeScanner.processImage(inputImage);
      if (kody.isNotEmpty) {
        kodEAN = kody.first.rawValue;
      }
    } catch (_) {}

    try {
      final ocr = await _textRecognizer.processImage(inputImage);
      _parsujTekst(ocr);
    } catch (_) {}

    final teraz = DateTime.now();
    final godzina = "${teraz.hour.toString().padLeft(2, '0')}:${teraz.minute.toString().padLeft(2, '0')}:${teraz.second.toString().padLeft(2, '0')}";

    _historia.insert(
      0,
      RaportHistorii(
        czas: godzina,
        sciezkaPliku: plik.path,
        produkt: produkt,
        data: dataWaznosci,
        partia: numerPartii,
        waga: masaNetto,
        wni: kodWNI,
        dostawca: nazwaDostawcy,
        ean: kodEAN,
      ),
    );

    setState(() {
      _laduje = false;
    });
  }

  void _resetujDane() {
    produkt = null;
    dataWaznosci = null;
    numerPartii = null;
    masaNetto = null;
    kodWNI = null;
    nazwaDostawcy = null;
    kodEAN = null;
  }

  void _parsujTekst(RecognizedText ocr) {
    List<String> linie = [];
    for (var b in ocr.blocks) {
      for (var l in b.lines) {
        linie.add(l.text.trim());
      }
    }

    String calosc = linie.join("\n").toUpperCase();

    // Produkt
    if (calosc.contains("KOTLETY")) {
      produkt = "MIĘSO NA KOTLETY Z INDYKA";
    } else if (calosc.contains("GULASZ")) {
      produkt = "MIĘSO NA GULASZ Z SZYNKI";
    } else if (calosc.contains("ROSOŁOWA")) {
      produkt = "PORCJA ROSOŁOWA WOŁOWA";
    } else if (calosc.contains("ŻEBERKA") || calosc.contains("ZEBERKA")) {
      produkt = "ŻEBERKA WIEPRZOWE";
    }

    // WNI
    for (var k in bazaWNI.keys) {
      if (calosc.replaceAll(RegExp(r'\s+'), '').contains(k)) {
        kodWNI = k;
        nazwaDostawcy = bazaWNI[k];
        break;
      }
    }
    if (kodWNI == null) {
      final regWniOwal = RegExp(r'(?:PL\s*)?(\d{8})(?:\s*WE)?');
      final matchWni = regWniOwal.firstMatch(calosc.replaceAll(" ", ""));
      if (matchWni != null && matchWni.group(1) != kodEAN) {
        kodWNI = matchWni.group(1);
        nazwaDostawcy = bazaWNI[kodWNI] ?? "Zakład spoza listy";
      }
    }

    // Data i Partia (analiza pionowa)
    final regData = RegExp(r'(\b\d{2}[.\-/]\d{2}[.\-/]\d{4}\b)');
    for (int i = 0; i < linie.length; i++) {
      final match = regData.firstMatch(linie[i]);
      if (match != null) {
        dataWaznosci = match.group(0);

        if (i + 1 < linie.length) {
          String podSpodem = linie[i + 1].trim();
          final regPartiaLinia = RegExp(r'^[A-Z0-9\-/]{4,15}$');
          if (regPartiaLinia.hasMatch(podSpodem) && !podSpodem.contains("PRZECH") && !podSpodem.contains("MASA")) {
            numerPartii = podSpodem;
          }
        }
        break;
      }
    }

    if (numerPartii == null) {
      for (int i = 0; i < linie.length; i++) {
        String l = linie[i].toUpperCase();
        if (l.contains("NUMER PARTII") || l.contains("NR PARTII") || l.contains("LOT")) {
          final regCyfry = RegExp(r'(\d{6,14})');
          final mCyfry = regCyfry.firstMatch(l);
          if (mCyfry != null) {
            numerPartii = mCyfry.group(1);
          } else if (i + 1 < linie.length) {
            final regNastepna = RegExp(r'^[A-Z0-9\-/]{4,15}$');
            if (regNastepna.hasMatch(linie[i + 1].trim())) {
              numerPartii = linie[i + 1].trim();
            }
          }
          break;
        }
      }
    }

    // Masa
    final regWaga = RegExp(r'(\d+[.,]?\d*)\s*(KG|G)\b');
    final matchWaga = regWaga.firstMatch(calosc);
    if (matchWaga != null) {
      masaNetto = "${matchWaga.group(1)} ${matchWaga.group(2)}";
    }
  }

  Widget _kafelek(String tytul, String? wartosc, String brak) {
    bool ok = wartosc != null && wartosc.isNotEmpty;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ok ? Colors.green : Colors.red.shade300),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(tytul, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Flexible(
            child: Text(
              ok ? wartosc! : brak,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: ok ? Colors.green.shade900 : Colors.red.shade900,
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
        title: Text(_indeksZakladki == 0 ? "Kontrola Etykiet DC06" : "Historia Kontroli (${_historia.length})"),
        backgroundColor: Colors.orange.shade800,
        actions: [
          if (_indeksZakladki == 1 && _historia.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_forever),
              tooltip: "Wyczyść historię",
              onPressed: () => setState(() => _historia.clear()),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _indeksZakladki,
        selectedItemColor: Colors.orange.shade900,
        onTap: (i) => setState(() => _indeksZakladki = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: "Skaner"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "Historia"),
        ],
      ),
      body: _indeksZakladki == 0 ? _widokSkanera() : _widokHistorii(),
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
                  onPressed: _laduje ? null : () => _zrobSkan(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt, color: Colors.white),
                  label: const Text("Aparat", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _laduje ? null : () => _zrobSkan(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library, color: Colors.white),
                  label: const Text("Z galerii", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_laduje)
            const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          if (_zdjecie != null && !_laduje) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(_zdjecie!, height: 160, width: double.infinity, fit: BoxFit.cover),
            ),
            const SizedBox(height: 10),
            _kafelek("Produkt", produkt, "NIE ROZPOZNANO"),
            _kafelek("Termin ważności", dataWaznosci, "BRAK DATY"),
            _kafelek("Numer partii", numerPartii, "BRAK PARTII"),
            _kafelek("Masa netto", masaNetto, "BRAK WAGI"),
            _kafelek("Stempel WNI", kodWNI, "BRAK (SPRAWDŹ SPÓD)"),
            _kafelek("Dostawca", nazwaDostawcy, "BRAK W BAZIE"),
            _kafelek("Kod EAN", kodEAN, "BRAK (SPRAWDŹ SPÓD)"),
          ],
        ],
      ),
    );
  }

  Widget _widokHistorii() {
    if (_historia.isEmpty) {
      return const Center(child: Text("Brak zapisanych kontroli. Zrób skan."));
    }
    return ListView.builder(
      itemCount: _historia.length,
      itemBuilder: (context, i) {
        final el = _historia[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(File(el.sciezkaPliku), width: 70, height: 70, fit: BoxFit.cover),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(el.czas, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                          Text(el.waga ?? "--", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                        ],
                      ),
                      Text(el.produkt ?? "Produkt nieznany", style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text("Data: ${el.data ?? '--'} | Partia: ${el.partia ?? '--'}"),
                      Text("Dostawca: ${el.dostawca ?? el.wni ?? '--'}", style: const TextStyle(fontSize: 11, color: Colors.black54)),
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
