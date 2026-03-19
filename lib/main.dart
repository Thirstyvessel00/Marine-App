
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const FishingApp());

class FishingApp extends StatelessWidget {
  const FishingApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'WA Offshore Toolkit',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
        home: const MapScreen(),
      );
}

class Wms {
  static const gebco = 'https://wms.gebco.net/mapserv?';
  static const gebcoLayer = 'GEBCO_LATEST';

  static const aodnNcwms = 'https://geoserver-123.aodn.org.au/geoserver/ncwms?';
  static const sst = 'srs_ghrsst_l3s_gm_1d_ngt_url/sea_surface_temperature';
  static const chla = 'srs_oc_snpp_chl_gsm_url/chl_gsm';

  static const oscar = 'https://coastwatch.pfeg.noaa.gov/erddap/wms/pmelOscar/request?';
  static const oscarLayer = '';// set a valid layer after checking capabilities

  // True color global Sentinel-2 cloudless via EOX (demo)
  static const eox = 'https://tiles.maps.eox.at/wms?';
  static const eoxLayer = 's2cloudless-2021_3857';
}

class MapScreen extends StatefulWidget { const MapScreen({super.key}); @override State<MapScreen> createState()=>_MapScreenState(); }

class _MapScreenState extends State<MapScreen> {
  final map = MapController();
  LatLng center = const LatLng(-31.95,115.86);

  // layer toggles
  bool showBath = true;
  bool showTrueColor = false;
  bool showSst = true;
  bool showChla = false;
  bool showCurr = false;
  bool showWind = true;

  // opacities
  double opTrue = 0.8, opSst = 0.8, opChla = 0.8, opCurr = 0.8, opBath = 0.6;

  // time control (last 7 days)
  DateTime today = DateTime.now().toUtc();
  int dayOffset = 0; // 0=today, 1=yesterday, etc.
  String get timeParam => DateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'").format(today.subtract(Duration(days: dayOffset)));

  // wind grid
  List<_Wind> wind = [];
  bool loadingWind=false;

  // waypoints
  List<_Wp> wps = [];

  @override
  void initState(){
    super.initState();
    _loadWps();
    _fetchWind();
  }

  Future<void> _loadWps() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('wps');
    if(raw!=null){
      final List list = json.decode(raw);
      wps = list.map((e)=>_Wp(LatLng(e['lat'], e['lon']), e['name'] as String)).toList();
      setState((){});
    }
  }

  Future<void> _saveWps() async{
    final sp = await SharedPreferences.getInstance();
    final list = wps.map((w)=>{'lat':w.p.latitude,'lon':w.p.longitude,'name':w.name}).toList();
    await sp.setString('wps', json.encode(list));
  }

  Future<void> _addWpAt(LatLng p) async{
    final name = await showDialog<String>(context: context, builder: (ctx){
      final c = TextEditingController();
      return AlertDialog(title: const Text('New waypoint'),content: TextField(controller:c, decoration: const InputDecoration(hintText:'Name (e.g., FAD #3)')),actions:[
        TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: ()=>Navigator.pop(ctx,c.text.isEmpty? 'WP': c.text), child: const Text('Save')),
      ]);
    });
    if(name!=null){ setState(()=> wps.add(_Wp(p,name))); await _saveWps(); }
  }

  Future<void> _locateMe() async{
    final ok = await Geolocator.requestPermission();
    if(ok==LocationPermission.deniedForever){ return; }
    final pos = await Geolocator.getCurrentPosition();
    final p = LatLng(pos.latitude, pos.longitude);
    setState(()=>center=p);
    map.move(p, 11);
  }

  Future<void> _fetchWind() async{
    setState(()=>loadingWind=true);
    final p = center; // simple box around center
    final url = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=${p.latitude.toStringAsFixed(3)}&longitude=${p.longitude.toStringAsFixed(3)}&hourly=wind_speed_10m,wind_direction_10m&timezone=auto');
    try{
      final r = await http.get(url);
      if(r.statusCode==200){
        final j = json.decode(r.body);
        final hourly = j['hourly'];
        final speeds = List<double>.from((hourly['wind_speed_10m'] as List).map((x)=>(x as num).toDouble()));
        final dirs = List<double>.from((hourly['wind_direction_10m'] as List).map((x)=>(x as num).toDouble()));
        if(speeds.isNotEmpty){
          final spd = speeds.last; final dir = dirs.last;
          final List<_Wind> list=[];
          const step=0.5; const span=2.0;
          for(double lat=p.latitude-span; lat<=p.latitude+span; lat+=step){
            for(double lon=p.longitude-span; lon<=p.longitude+span; lon+=step){
              list.add(_Wind(LatLng(lat,lon), spd, dir));
            }
          }
          setState(()=>wind=list);
        }
      }
    } finally { setState(()=>loadingWind=false); }
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: const Text('WA Offshore Toolkit')),
      body: GestureDetector(
        onLongPressStart: (d){
          // convert global position to latlng
          final rb = (context.findRenderObject() as RenderBox);
          final local = rb.globalToLocal(d.globalPosition);
          final crs = const Epsg3857();
          final p = map.camera.pointToLatLng(CustomPoint(local.dx, local.dy));
          _addWpAt(p);
        },
        child: Stack(children:[
          FlutterMap(
            mapController: map,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 6,
              onTap: (_, __) {},
            ),
            children:[
              // Base (OSM demo only)
              TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName:'au.wa.offshore.toolkit'),

              if(showTrueColor)
                TileLayer(
                  opacity: opTrue,
                  wmsOptions: WMSTileLayerOptions(baseUrl: Wms.eox, layers: const [Wms.eoxLayer], transparent: true, version: '1.3.0'),
                ),

              if(showBath)
                TileLayer(
                  opacity: opBath,
                  wmsOptions: WMSTileLayerOptions(baseUrl: Wms.gebco, layers: const [Wms.gebcoLayer], transparent: true, version: '1.3.0'),
                ),

              if(showSst)
                TileLayer(
                  opacity: opSst,
                  wmsOptions: WMSTileLayerOptions(
                    baseUrl: Wms.aodnNcwms,
                    layers: const [Wms.sst],
                    transparent: true,
                    version: '1.3.0',
                    otherParameters: { 'TIME': timeParam, 'COLORSCALERANGE':'10,30','NUMCOLORBANDS':'250'},
                  ),
                ),

              if(showChla)
                TileLayer(
                  opacity: opChla,
                  wmsOptions: WMSTileLayerOptions(
                    baseUrl: Wms.aodnNcwms,
                    layers: const [Wms.chla],
                    transparent: true,
                    version: '1.3.0',
                    otherParameters: { 'TIME': timeParam, 'COLORSCALERANGE':'0.03,3','NUMCOLORBANDS':'250'},
                  ),
                ),

              if(showCurr && Wms.oscarLayer.isNotEmpty)
                TileLayer(
                  opacity: opCurr,
                  wmsOptions: WMSTileLayerOptions(baseUrl: Wms.oscar, layers: const [Wms.oscarLayer], transparent: true, version: '1.3.0'),
                ),

              if(showWind) WindOverlay(vectors: wind),

              // Waypoints
              MarkerLayer(markers: wps.map((w)=>Marker(width:100,height:50,point:w.p,builder:(ctx)=>Column(children:[
                const Icon(Icons.place, color: Colors.yellow),
                Container(padding: const EdgeInsets.symmetric(horizontal:6, vertical:2), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)), child: Text(w.name, style: const TextStyle(color: Colors.white, fontSize: 11)))
              ]))).toList()),
            ],
          ),

          // UI: layer toggles & opacity
          Positioned(left:8,bottom:8, child: _panel()),

          // UI: time slider
          Positioned(right:8,bottom:8, child: _timePanel()),

          // locate & coords
          Positioned(right:8, top:8, child: Column(children:[
            FilledButton.icon(onPressed: _locateMe, icon: const Icon(Icons.my_location), label: const Text('Locate')),
            const SizedBox(height:8),
            FilledButton.icon(onPressed: _fetchWind, icon: const Icon(Icons.air), label: const Text('Refresh wind')),
          ])),

          if(loadingWind) const Positioned(right:12, top:100, child: Card(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))),
        ]),
      ),
    );
  }

  Widget _panel(){
    return Card(child: SizedBox(width:300, child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children:[
      const Text('Layers', style: TextStyle(fontWeight: FontWeight.bold)),
      _chk('True color (S2 cloudless)', showTrueColor, (v)=> setState(()=> showTrueColor=v), slider: _op(opTrue, (v)=> setState(()=> opTrue=v))),
      _chk('Bathymetry (GEBCO)', showBath, (v)=> setState(()=> showBath=v), slider: _op(opBath, (v)=> setState(()=> opBath=v))),
      _chk('SST (IMOS)', showSst, (v)=> setState(()=> showSst=v), slider: _op(opSst, (v)=> setState(()=> opSst=v))),
      _chk('Chl‑a (IMOS)', showChla, (v)=> setState(()=> showChla=v), slider: _op(opChla, (v)=> setState(()=> opChla=v))),
      _chk('Currents (OSCAR)', showCurr, (v)=> setState(()=> showCurr=v), slider: _op(opCurr, (v)=> setState(()=> opCurr=v))),
      _chk('Wind arrows', showWind, (v)=> setState(()=> showWind=v)),
      const Divider(),
      Text('Waypoints: ${wps.length}'),
      Wrap(spacing:6, children: wps.map((w)=>InputChip(label: Text(w.name), onDeleted: () async{ setState(()=> wps.remove(w)); await _saveWps(); })).toList()),
    ]))));
  }

  Widget _chk(String label, bool value, void Function(bool) onChanged, {Widget? slider}){
    return Row(children:[
      Checkbox(value:value, onChanged: (v)=> onChanged(v??false)),
      Expanded(child: Text(label)),
      if(slider!=null) SizedBox(width:120, child: slider),
    ]);
  }

  Widget _op(double value, ValueChanged<double> onChanged){
    return Slider(value:value, onChanged:onChanged, min:0.0, max:1.0);
  }

  Widget _timePanel(){
    return Card(child: Padding(padding: const EdgeInsets.all(10), child: Column(mainAxisSize: MainAxisSize.min, children:[
      const Text('Time (last 7 days)'),
      Row(children:[
        const Text('-7d'),
        Expanded(child: Slider(value: dayOffset.toDouble(), onChanged:(v){ setState(()=> dayOffset=v.round()); }, min:0, max:7, divisions:7)),
        const Text('Now'),
      ]),
      Text(DateFormat('yyyy-MM-dd HH:mm').format(today.subtract(Duration(days: dayOffset)))+' UTC')
    ])));
  }
}

class _Wind{ final LatLng p; final double spdKmh; final double dirDeg; _Wind(this.p, this.spdKmh, this.dirDeg);} 

class WindOverlay extends StatelessWidget{
  final List<_Wind> vectors; const WindOverlay({super.key, required this.vectors});
  @override Widget build(BuildContext context){
    return MarkerLayer(markers: vectors.map((v){
      final rad = (270 - v.dirDeg) * math.pi / 180.0; // meteorological -> math
      final dx = math.cos(rad), dy = math.sin(rad);
      final len = (v.spdKmh / 30.0).clamp(0.5, 2.0);
      return Marker(point: v.p, width:44, height:44, builder: (_) => CustomPaint(painter: _Arrow(dx:dx,dy:dy,scale:len)));
    }).toList());
  }
}

class _Arrow extends CustomPainter{ final double dx,dy,scale; const _Arrow({required this.dx,required this.dy,required this.scale});
  @override void paint(Canvas c, Size s){ final ct=Offset(s.width/2,s.height/2); final p=Paint()..color=Colors.orangeAccent..strokeWidth=2..style=PaintingStyle.stroke; final head=Offset(ct.dx+dx*12*scale, ct.dy+dy*12*scale); c.drawLine(ct, head, p); final perp=Offset(-dy,dx); final left=head-Offset(dx,dy)*4*scale+perp*3*scale; final right=head-Offset(dx,dy)*4*scale-perp*3*scale; final path=Path()..moveTo(head.dx,head.dy)..lineTo(left.dx,left.dy)..moveTo(head.dx,head.dy)..lineTo(right.dx,right.dy); c.drawPath(path,p); }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate)=>false; }

class _Wp{ final LatLng p; final String name; _Wp(this.p,this.name); }
