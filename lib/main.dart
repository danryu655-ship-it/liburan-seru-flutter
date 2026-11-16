import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'data/destinations.dart';

void main() => runApp(const LiburanSeruApp());

String formatIDR(double v) {
  final neg = v < 0;
  var s = v.abs().round().toString();
  final buf = StringBuffer();
  var c = 0;
  for (var i = s.length - 1; i >= 0; i--) {
    buf.write(s[i]);
    c++;
    if (c % 3 == 0 && i != 0) buf.write('.');
  }
  final rev = buf.toString().split('').reversed.join();
  return '${neg ? '-' : ''}Rp$rev';
}

String formatForeign(double v, String cur) {
  final s = v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2);
  return '$cur $s';
}

const List<String> statuses = ['Belum Bayar', 'DP', 'Lunas'];

class JastipItem {
  JastipItem({
    required this.id,
    required this.penitip,
    required this.barang,
    required this.currency,
    required this.hargaAsing,
    required this.status,
  });
  final String id;
  final String penitip;
  final String barang;
  final String currency;
  final double hargaAsing;
  final String status;
  double idr(Map<String, double> rates) => hargaAsing * (rates[currency] ?? 1);
  Map<String, dynamic> toJson() => {
        'id': id,
        'penitip': penitip,
        'barang': barang,
        'currency': currency,
        'hargaAsing': hargaAsing,
        'status': status,
      };
  factory JastipItem.fromJson(Map<String, dynamic> j) => JastipItem(
        id: j['id'] as String? ?? '',
        penitip: j['penitip'] as String? ?? '',
        barang: j['barang'] as String? ?? '',
        currency: j['currency'] as String? ?? 'JPY',
        hargaAsing: (j['hargaAsing'] as num? ?? 0).toDouble(),
        status: j['status'] as String? ?? 'Belum Bayar',
      );
}

const List<String> itinStatuses = ['Wishlist', 'Planned', 'Done'];

String formatDate(DateTime? d) =>
    d == null ? 'Pilih tanggal' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class ItinActivity {
  ItinActivity({required this.id, required this.name, required this.location, required this.date, required this.cost, required this.status});
  final String id;
  final String name;
  final String location;
  final String date; // yyyy-MM-dd atau ''
  final double cost;
  final String status;
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'location': location, 'date': date, 'cost': cost, 'status': status};
  factory ItinActivity.fromJson(Map<String, dynamic> j) => ItinActivity(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        location: j['location'] as String? ?? '',
        date: j['date'] as String? ?? '',
        cost: (j['cost'] as num? ?? 0).toDouble(),
        status: j['status'] as String? ?? 'Wishlist',
      );
}

class LiburanSeruApp extends StatelessWidget {
  const LiburanSeruApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Liburan Seru',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0E7C7B),
          primary: const Color(0xFF0E7C7B),
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  List<JastipItem> _items = [];
  Map<String, double> _rates = Map.of(defaultRates);
  String _jastipCurrency = 'JPY';
  List<ItinActivity> _itinActivities = [];
  String _itinRoute = '';
  DateTime? _itinDepart;
  DateTime? _itinReturn;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final itemsRaw = prefs.getString('ls_jastip_items');
    final ratesRaw = prefs.getString('ls_rates');
    final itinRaw = prefs.getString('ls_itinerary');
    setState(() {
      if (itemsRaw != null) {
        try {
          final list = jsonDecode(itemsRaw) as List;
          _items = list.map((e) => JastipItem.fromJson(e as Map<String, dynamic>)).toList();
        } catch (_) {}
      }
      if (ratesRaw != null) {
        try {
          final m = jsonDecode(ratesRaw) as Map<String, dynamic>;
          for (final e in m.entries) {
            _rates[e.key] = (e.value as num).toDouble();
          }
        } catch (_) {}
      }
      if (itinRaw != null) {
        try {
          final m = jsonDecode(itinRaw) as Map<String, dynamic>;
          _itinRoute = m['route'] as String? ?? '';
          final dep = m['depart'] as String?;
          final ret = m['return'] as String?;
          _itinDepart = dep == null || dep.isEmpty ? null : DateTime.tryParse(dep);
          _itinReturn = ret == null || ret.isEmpty ? null : DateTime.tryParse(ret);
          final list = m['activities'] as List? ?? [];
          _itinActivities = list.map((e) => ItinActivity.fromJson(e as Map<String, dynamic>)).toList();
        } catch (_) {}
      }
      _loaded = true;
    });
  }

  Future<void> _saveItems() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ls_jastip_items', jsonEncode(_items.map((e) => e.toJson()).toList()));
  }

  Future<void> _saveRates() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ls_rates', jsonEncode(_rates));
  }

  void _addItem(JastipItem item) {
    setState(() => _items.insert(0, item));
    _saveItems();
  }

  void _deleteItem(String id) {
    setState(() => _items.removeWhere((e) => e.id == id));
    _saveItems();
  }

  void _cycleStatus(String id) {
    setState(() {
      final i = _items.indexWhere((e) => e.id == id);
      if (i < 0) return;
      final old = _items[i];
      final next = statuses[(statuses.indexOf(old.status) + 1) % statuses.length];
      _items[i] = JastipItem(id: old.id, penitip: old.penitip, barang: old.barang, currency: old.currency, hargaAsing: old.hargaAsing, status: next);
    });
    _saveItems();
  }

  Future<void> _saveItinerary() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ls_itinerary', jsonEncode({
      'route': _itinRoute,
      'depart': _itinDepart?.toIso8601String() ?? '',
      'return': _itinReturn?.toIso8601String() ?? '',
      'activities': _itinActivities.map((e) => e.toJson()).toList(),
    }));
  }

  void _updateItinPlan(String route, DateTime? depart, DateTime? ret) {
    setState(() {
      _itinRoute = route;
      _itinDepart = depart;
      _itinReturn = ret;
    });
    _saveItinerary();
  }

  void _addItinActivity(ItinActivity a) {
    setState(() => _itinActivities.insert(0, a));
    _saveItinerary();
  }

  void _deleteItinActivity(String id) {
    setState(() => _itinActivities.removeWhere((e) => e.id == id));
    _saveItinerary();
  }

  void _cycleItinStatus(String id) {
    setState(() {
      final i = _itinActivities.indexWhere((e) => e.id == id);
      if (i < 0) return;
      final old = _itinActivities[i];
      final next = itinStatuses[(itinStatuses.indexOf(old.status) + 1) % itinStatuses.length];
      _itinActivities[i] = ItinActivity(id: old.id, name: old.name, location: old.location, date: old.date, cost: old.cost, status: next);
    });
    _saveItinerary();
  }

  void _addDestinationToItinerary(String city) {
    setState(() {
      _itinRoute = _itinRoute.isEmpty ? city : (_itinRoute.contains(city) ? _itinRoute : '$_itinRoute -> $city');
      _tab = 2;
    });
    _saveItinerary();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$city ditambahkan ke rute perjalanan.')));
  }

  void _openJastipPage() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('Jastip'), backgroundColor: const Color(0xFF0E7C7B), foregroundColor: Colors.white),
      body: JastipScreen(items: _items, rates: _rates, currency: _jastipCurrency, onCurrencyChanged: (c) => setState(() => _jastipCurrency = c), onAdd: _addItem, onDelete: _deleteItem, onCycleStatus: _cycleStatus),
    )));
  }

  void _openKursPage() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('Kurs'), backgroundColor: const Color(0xFF0E7C7B), foregroundColor: Colors.white),
      body: KursScreen(rates: _rates, onRatesChanged: _updateRates),
    )));
  }

  void _goToJastip(String currency) {
    setState(() => _jastipCurrency = currency);
    _openJastipPage();
  }

  void _updateRates(Map<String, double> rates) {
    setState(() => _rates = rates);
    _saveRates();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Liburan Seru'),
        backgroundColor: const Color(0xFF0E7C7B),
        foregroundColor: Colors.white,
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : switch (_tab) {
              0 => PesananScreen(
                  items: _items,
                  rates: _rates,
                  onOpenJastip: _openJastipPage,
                  onOpenKurs: _openKursPage,
                ),
              1 => TravelScreen(onJastipFrom: _goToJastip, onAddToItinerary: _addDestinationToItinerary),
              _ => ItineraryScreen(
                  route: _itinRoute,
                  depart: _itinDepart,
                  ret: _itinReturn,
                  activities: _itinActivities,
                  onPlanChanged: _updateItinPlan,
                  onAdd: _addItinActivity,
                  onDelete: _deleteItinActivity,
                  onCycleStatus: _cycleItinStatus,
                ),
            },
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        selectedItemColor: const Color(0xFF0E7C7B),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'Pesanan'),
          BottomNavigationBarItem(icon: Icon(Icons.flight), label: 'Travel'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Itinerary'),
        ],
      ),
    );
  }
}

class JastipScreen extends StatefulWidget {
  const JastipScreen({super.key, required this.items, required this.rates, required this.currency, required this.onCurrencyChanged, required this.onAdd, required this.onDelete, required this.onCycleStatus});
  final List<JastipItem> items;
  final Map<String, double> rates;
  final String currency;
  final ValueChanged<String> onCurrencyChanged;
  final ValueChanged<JastipItem> onAdd;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onCycleStatus;
  @override
  State<JastipScreen> createState() => _JastipScreenState();
}

class _JastipScreenState extends State<JastipScreen> {
  final _penitip = TextEditingController();
  final _barang = TextEditingController();
  final _harga = TextEditingController();
  String _status = 'Belum Bayar';
  String _filter = 'Semua';

  @override
  void dispose() {
    _penitip.dispose();
    _barang.dispose();
    _harga.dispose();
    super.dispose();
  }

  void _submit() {
    final penitip = _penitip.text.trim();
    final barang = _barang.text.trim();
    final harga = double.tryParse(_harga.text.trim().replaceAll(',', '.'));
    if (penitip.isEmpty || barang.isEmpty || harga == null || harga <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Isi nama penitip, nama barang, dan harga yang benar.')));
      return;
    }
    widget.onAdd(JastipItem(id: DateTime.now().millisecondsSinceEpoch.toString(), penitip: penitip, barang: barang, currency: widget.currency, hargaAsing: harga, status: _status));
    _penitip.clear();
    _barang.clear();
    _harga.clear();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Titipan $barang dari $penitip ditambahkan.')));
  }

  Color _statusColor(String s) => switch (s) {
        'Lunas' => Colors.green,
        'DP' => Colors.orange,
        _ => Colors.red,
      };

  @override
  Widget build(BuildContext context) {
    final total = widget.items.fold<double>(0, (a, e) => a + e.idr(widget.rates));
    final lunas = widget.items.where((e) => e.status == 'Lunas').length;
    final belumTotal = widget.items.where((e) => e.status != 'Lunas').fold<double>(0, (a, e) => a + e.idr(widget.rates));
    final shown = _filter == 'Semua' ? widget.items : widget.items.where((e) => e.status == _filter).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Image.asset('assets/logo_full.png', height: 110, fit: BoxFit.contain),
        ),
        const SizedBox(height: 8),
        Card(
          color: const Color(0xFF0E7C7B),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total Nilai Jastip', style: TextStyle(color: Colors.white70)),
                Text(formatIDR(total), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('${widget.items.length} titipan • $lunas lunas • Belum lunas ${formatIDR(belumTotal)}', style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Tambah Titipan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(controller: _penitip, decoration: const InputDecoration(labelText: 'Nama Penitip', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: _barang, decoration: const InputDecoration(labelText: 'Nama Barang', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                initialValue: widget.currency,
                decoration: const InputDecoration(labelText: 'Mata Uang', border: OutlineInputBorder()),
                items: currencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) { if (v != null) widget.onCurrencyChanged(v); },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextField(controller: _harga, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Harga Asing', border: OutlineInputBorder())),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status Pembayaran', border: OutlineInputBorder()),
                items: statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) { if (v != null) setState(() => _status = v); },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Estimasi: ${formatIDR((double.tryParse(_harga.text.trim().replaceAll(',', '.')) ?? 0) * (widget.rates[widget.currency] ?? 1))}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.add), label: const Text('Tambah Titipan')),
        ),
        const SizedBox(height: 8),
        Text('Kurs ${widget.currency}: 1 ${widget.currency} = ${formatIDR(widget.rates[widget.currency] ?? 1)} (bisa diubah di tab Kurs). Data tersimpan offline di HP.', style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: ['Semua', ...statuses].map((f) {
            return ChoiceChip(label: Text(f), selected: _filter == f, onSelected: (_) => setState(() => _filter = f));
          }).toList(),
        ),
        const SizedBox(height: 8),
        if (shown.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Belum ada titipan. Tambahkan di atas.'))),
        ...shown.map((item) {
          return Card(
            child: ListTile(
              title: Text('${item.barang} — ${item.penitip}'),
              subtitle: Text('${formatForeign(item.hargaAsing, item.currency)}  •  ${formatIDR(item.idr(widget.rates))}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => widget.onCycleStatus(item.id),
                    child: Chip(label: Text(item.status, style: const TextStyle(color: Colors.white, fontSize: 12)), backgroundColor: _statusColor(item.status)),
                  ),
                  IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => widget.onDelete(item.id)),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

class TravelScreen extends StatefulWidget {
  const TravelScreen({super.key, required this.onJastipFrom, required this.onAddToItinerary});
  final ValueChanged<String> onJastipFrom;
  final ValueChanged<String> onAddToItinerary;
  @override
  State<TravelScreen> createState() => _TravelScreenState();
}

class _TravelScreenState extends State<TravelScreen> {
  String _query = '';
  String _region = 'Semua';
  @override
  Widget build(BuildContext context) {
    final regions = ['Semua', 'Asia', 'Eropa', 'Amerika', 'Timur Tengah', 'Oseania'];
    final shown = destinations.where((d) {
      final okRegion = _region == 'Semua' || d.region == _region;
      final q = _query.toLowerCase();
      final okQuery = q.isEmpty || d.name.toLowerCase().contains(q) || d.country.toLowerCase().contains(q);
      return okRegion && okQuery;
    }).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            decoration: const InputDecoration(hintText: 'Cari kota atau negara… (mis. Tokyo, Bali)', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: regions.map((r) {
              return Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(r), selected: _region == r, onSelected: (_) => setState(() => _region = r)));
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: shown.length,
            itemBuilder: (context, i) {
              final d = shown[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: const Color(0xFF0E7C7B), foregroundColor: Colors.white, child: Text(d.name[0])),
                  title: Text('${d.name}, ${d.country}'),
                  subtitle: Text('${d.passName} • ${d.passPrice}\n${d.duration} • ${d.currency}'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => DestinationDetail(dest: d, onJastipFrom: widget.onJastipFrom, onAddToItinerary: widget.onAddToItinerary)));
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class DestinationDetail extends StatelessWidget {
  const DestinationDetail({super.key, required this.dest, required this.onJastipFrom, required this.onAddToItinerary});
  final Destination dest;
  final ValueChanged<String> onJastipFrom;
  final ValueChanged<String> onAddToItinerary;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${dest.name}, ${dest.country}'), backgroundColor: const Color(0xFF0E7C7B), foregroundColor: Colors.white),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dest.passName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('${dest.passPrice} • ${dest.duration}'),
                  Text('Mata uang: ${dest.currency} • Wilayah: ${dest.region}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Yang wajib dilihat', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ...dest.highlights.map((h) => ListTile(leading: const Icon(Icons.place, color: Color(0xFF0E7C7B)), title: Text(h))),
          const SizedBox(height: 8),
          const Text('Itinerary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ...dest.itinerary.map((s) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('•  $s'))),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onJastipFrom(dest.currency);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Mata uang Jastip diset ke ${dest.currency} (${dest.name}).')));
              },
              icon: const Icon(Icons.shopping_bag),
              label: Text('Buat Jastip dari ${dest.name}'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onAddToItinerary(dest.name);
              },
              icon: const Icon(Icons.map),
              label: Text('Masukkan ${dest.name} ke Rencana Perjalanan'),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Harga pass & itinerary adalah perkiraan. Cek harga terbaru sebelum berangkat.', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}

// ---------------- PESANAN ----------------

class PesananScreen extends StatelessWidget {
  const PesananScreen({super.key, required this.items, required this.rates, required this.onOpenJastip, required this.onOpenKurs});
  final List<JastipItem> items;
  final Map<String, double> rates;
  final VoidCallback onOpenJastip;
  final VoidCallback onOpenKurs;
  @override
  Widget build(BuildContext context) {
    final total = items.fold<double>(0, (a, e) => a + e.idr(rates));
    final lunas = items.where((e) => e.status == 'Lunas').length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(child: Image.asset('assets/logo_full.png', height: 110, fit: BoxFit.contain)),
        const SizedBox(height: 16),
        const Text('Pesanan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Text('Pilih salah satu untuk dibuka.', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 12),
        Card(
          child: InkWell(
            onTap: onOpenJastip,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const CircleAvatar(backgroundColor: Color(0xFF0E7C7B), foregroundColor: Colors.white, child: Icon(Icons.shopping_bag)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Jastip', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('${items.length} titipan • $lunas lunas\nTotal ${formatIDR(total)}'),
                  ])),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: InkWell(
            onTap: onOpenKurs,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const CircleAvatar(backgroundColor: Color(0xFFF58A1F), foregroundColor: Colors.white, child: Icon(Icons.currency_exchange)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Kurs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('1 USD = ${formatIDR(rates['USD'] ?? 1)} • 1 JPY = ${formatIDR(rates['JPY'] ?? 1)}\nKetuk untuk ubah kurs'),
                  ])),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------- ITINERARY ----------------

class ItineraryScreen extends StatefulWidget {
  const ItineraryScreen({super.key, required this.route, required this.depart, required this.ret, required this.activities, required this.onPlanChanged, required this.onAdd, required this.onDelete, required this.onCycleStatus});
  final String route;
  final DateTime? depart;
  final DateTime? ret;
  final List<ItinActivity> activities;
  final void Function(String route, DateTime? depart, DateTime? ret) onPlanChanged;
  final ValueChanged<ItinActivity> onAdd;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onCycleStatus;
  @override
  State<ItineraryScreen> createState() => _ItineraryScreenState();
}

class _ItineraryScreenState extends State<ItineraryScreen> {
  late final TextEditingController _route = TextEditingController(text: widget.route);
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _cost = TextEditingController();
  DateTime? _date;
  String _status = 'Wishlist';

  @override
  void didUpdateWidget(ItineraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.route != oldWidget.route && widget.route != _route.text) {
      _route.text = widget.route;
    }
  }

  @override
  void dispose() {
    _route.dispose();
    _name.dispose();
    _location.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isDepart) async {
    final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2026), lastDate: DateTime(2028));
    if (picked == null) return;
    widget.onPlanChanged(_route.text.trim(), isDepart ? picked : widget.depart, isDepart ? widget.ret : picked);
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Isi nama aktivitas dulu.')));
      return;
    }
    final cost = double.tryParse(_cost.text.trim().replaceAll(',', '.')) ?? 0;
    widget.onAdd(ItinActivity(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      location: _location.text.trim(),
      date: _date == null ? '' : '${_date!.year}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}',
      cost: cost,
      status: _status,
    ));
    _name.clear();
    _location.clear();
    _cost.clear();
    setState(() => _date = null);
  }

  Color _statusColor(String s) => switch (s) {
        'Done' => Colors.green,
        'Planned' => Colors.blue,
        _ => Colors.orange,
      };

  Widget _column(String title, IconData icon, List<ItinActivity> list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(children: [Icon(icon, color: const Color(0xFF0E7C7B)), const SizedBox(width: 6), Text('$title (${list.length})', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))]),
        const SizedBox(height: 8),
        if (list.isEmpty) const Text('Belum ada — tambahkan aktivitas di atas.', style: TextStyle(color: Colors.grey)),
        ...list.map((a) => Card(
              child: ListTile(
                title: Text(a.name),
                subtitle: Text('${a.location.isEmpty ? '-' : a.location}${a.date.isEmpty ? '' : ' • ${a.date}'}\n${formatIDR(a.cost)}'),
                isThreeLine: true,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  InkWell(
                    onTap: () => widget.onCycleStatus(a.id),
                    child: Chip(label: Text(a.status, style: const TextStyle(color: Colors.white, fontSize: 12)), backgroundColor: _statusColor(a.status)),
                  ),
                  IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => widget.onDelete(a.id)),
                ]),
              ),
            )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.activities.fold<double>(0, (a, e) => a + e.cost);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Advanced Itinerary Planner', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Text('Rancang perjalanan multi-kota, atur jadwal, kelola anggaran.', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 12),
        TextField(
          controller: _route,
          decoration: const InputDecoration(labelText: 'Tujuan Multi-Kota', hintText: 'Cth: Nagoya -> Shirakawa -> Kyoto', border: OutlineInputBorder()),
          onChanged: (v) => widget.onPlanChanged(v, widget.depart, widget.ret),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _pickDate(true), icon: const Icon(Icons.calendar_today, size: 18), label: Text('Pergi: ${formatDate(widget.depart)}'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => _pickDate(false), icon: const Icon(Icons.calendar_today, size: 18), label: Text('Sampai: ${formatDate(widget.ret)}'))),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              widget.onPlanChanged(_route.text.trim(), widget.depart, widget.ret);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rencana disimpan di HP.')));
            },
            icon: const Icon(Icons.save),
            label: const Text('Simpan Rencana'),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Tambah Aktivitas', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Aktivitas (Cth: Bermain Salju)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: _location, decoration: const InputDecoration(labelText: 'Lokasi (Cth: Shirakawa)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: OutlinedButton.icon(onPressed: () async {
              final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2026), lastDate: DateTime(2028));
              if (picked != null) setState(() => _date = picked);
            }, icon: const Icon(Icons.calendar_today, size: 18), label: Text(formatDate(_date)))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Biaya (IDR)', border: OutlineInputBorder()))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: DropdownButtonFormField<String>(initialValue: _status, decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()), items: itinStatuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) { if (v != null) setState(() => _status = v); })),
            const SizedBox(width: 8),
            Expanded(child: FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.add), label: const Text('+ Tambah'))),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          color: const Color(0xFFFFF3E0),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Estimasi Total Pengeluaran:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(formatIDR(total), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 18)),
            ]),
          ),
        ),
        _column('Wishlist', Icons.star, widget.activities.where((e) => e.status == 'Wishlist').toList()),
        _column('Planned (To Do)', Icons.event_note, widget.activities.where((e) => e.status == 'Planned').toList()),
        _column('Done', Icons.check_circle, widget.activities.where((e) => e.status == 'Done').toList()),
        const SizedBox(height: 8),
        const Text('Ketuk chip status untuk pindah kolom: Wishlist → Planned → Done. Semua tersimpan offline di HP.', style: TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}

class KursScreen extends StatefulWidget {
  const KursScreen({super.key, required this.rates, required this.onRatesChanged});
  final Map<String, double> rates;
  final ValueChanged<Map<String, double>> onRatesChanged;
  @override
  State<KursScreen> createState() => _KursScreenState();
}

class _KursScreenState extends State<KursScreen> {
  bool _loading = false;

  Future<void> _editRate(String cur) async {
    final ctrl = TextEditingController(text: (widget.rates[cur] ?? 1).toStringAsFixed(0));
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Kurs 1 $cur = ? IDR'),
        content: TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Simpan')),
        ],
      ),
    );
    if (result == null) return;
    final v = double.tryParse(result.trim().replaceAll(',', '.'));
    if (v == null || v <= 0) return;
    final next = Map<String, double>.of(widget.rates);
    next[cur] = v;
    widget.onRatesChanged(next);
  }

  Future<void> _refreshOnline() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('https://open.er-api.com/v6/latest/IDR')).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final rates = data['rates'] as Map<String, dynamic>;
      final next = Map<String, double>.of(widget.rates);
      var changed = 0;
      for (final cur in currencies) {
        if (cur == 'IDR') continue;
        final perIdr = (rates[cur] as num?)?.toDouble();
        if (perIdr != null && perIdr > 0) {
          next[cur] = 1 / perIdr;
          changed++;
        }
      }
      if (changed == 0) throw Exception('Tidak ada kurs');
      widget.onRatesChanged(next);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kurs diperbarui online ($changed mata uang).')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal ambil kurs online — pakai kurs manual yang tersimpan.')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Kurs ini hanya estimasi untuk hitung Jastip. Ubah manual bila perlu — tersimpan offline di HP.', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: FilledButton.icon(onPressed: _loading ? null : _refreshOnline, icon: const Icon(Icons.refresh), label: Text(_loading ? 'Mengambil…' : 'Perbarui Kurs Online'))),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                widget.onRatesChanged(Map.of(defaultRates));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kurs dikembalikan ke default.')));
              },
              child: const Text('Reset'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...currencies.where((c) => c != 'IDR').map((cur) {
          return Card(
            child: ListTile(title: Text('1 $cur'), subtitle: Text(formatIDR(widget.rates[cur] ?? 1)), trailing: const Icon(Icons.edit), onTap: () => _editRate(cur)),
          );
        }),
      ],
    );
  }
}
