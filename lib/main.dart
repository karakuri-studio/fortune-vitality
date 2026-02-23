import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    debugPrint('CameraError: ${e.description}');
  }
  runApp(const KarakuriApp());
}

// --- Design Tokens ---
class Tokens {
  static const sumi = Color(0xFF0A0906);
  static const sumi2 = Color(0xFF141109);
  static const sumi3 = Color(0xFF1C1810);
  static const washi = Color(0xFFF5EFE0);
  static const washi2 = Color(0xFFE0D8C4);
  static const washi3 = Color(0xFFC8BFA8);
  static const kin = Color(0xFFC9A84C);
  static const kin2 = Color(0xFFE8C56A);
  static const beni = Color(0xFFC0392B);
  static const gin = Color(0xFF8A9490);
  static const border = Color(0x23C9A84C); // 0.14 opacity
  static const border2 = Color(0x47C9A84C); // 0.28 opacity
}

// --- Data Models ---
class GearType {
  final String name;
  final String desc;
  const GearType(this.name, this.desc);
}

const List<GearType> gearTypes = [
  GearType('太陽歯車 (Sun Gear)', '周囲を牽引する中心動力。強烈な熱と力を持つリーダー気質。'),
  GearType('遊星歯車 (Planetary Gear)', '環境に合わせて軌道を変える、柔軟でトリッキーな機構。'),
  GearType('冠歯車 (Crown Gear)', '直角に動力を伝える。常識を覆す直感と発想力の源。'),
  GearType('脱進機 (Escapement)', '時を正確に刻む心臓部。極めて緻密で分析的な頭脳派。'),
];

class PalmPattern {
  final Path heart;
  final Path head;
  final Path life;
  PalmPattern(this.heart, this.head, this.life);
}

// ReactのSVG Path文字列をFlutterのPathオブジェクトに変換
List<PalmPattern> get palmPatterns => [
  PalmPattern(
    Path()
      ..moveTo(180, 80)
      ..quadraticBezierTo(120, 90, 40, 60),
    Path()
      ..moveTo(40, 100)
      ..quadraticBezierTo(120, 120, 180, 170),
    Path()
      ..moveTo(40, 100)
      ..quadraticBezierTo(60, 180, 100, 240),
  ),
  PalmPattern(
    Path()
      ..moveTo(190, 70)
      ..quadraticBezierTo(100, 100, 20, 60),
    Path()
      ..moveTo(30, 90)
      ..quadraticBezierTo(100, 130, 150, 200),
    Path()
      ..moveTo(30, 90)
      ..quadraticBezierTo(80, 160, 90, 230),
  ),
  PalmPattern(
    Path()
      ..moveTo(170, 90)
      ..quadraticBezierTo(130, 90, 50, 70),
    Path()
      ..moveTo(50, 110)
      ..quadraticBezierTo(140, 100, 190, 150),
    Path()
      ..moveTo(50, 110)
      ..quadraticBezierTo(50, 190, 120, 250),
  ),
  PalmPattern(
    Path()
      ..moveTo(185, 85)
      ..quadraticBezierTo(110, 80, 30, 70),
    Path()
      ..moveTo(40, 95)
      ..quadraticBezierTo(130, 110, 170, 140),
    Path()
      ..moveTo(40, 95)
      ..quadraticBezierTo(70, 150, 80, 230),
  ),
];

// --- Application ---
class KarakuriApp extends StatelessWidget {
  const KarakuriApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vitality Lens',
      theme: ThemeData(
        scaffoldBackgroundColor: Tokens.sumi,
        fontFamily: 'serif', // カスタムフォントがある場合は指定
        textTheme: const TextTheme(bodyMedium: TextStyle(color: Tokens.washi)),
      ),
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  String _step = 'intro';
  bool _isScanning = false;
  String _scanLog = '';
  int _scanProgress = 0;
  Uint8List? _capturedImageBytes;
  String _cameraError = '';

  double _focusLevel = 0.0;
  int _vitality = 0;
  List<int> _radarData = [0, 0, 0, 0, 0];
  late PalmPattern _currentPattern;
  late GearType _gearType;
  String _message = '';
  String _advice = '';

  List<Map<String, dynamic>> _historyData = [];

  CameraController? _cameraController;
  int _selectedCameraIdx = 0;

  Timer? _scanLogTimer;
  Timer? _scanTimeoutTimer;
  Timer? _autoFocusTimer;

  late AnimationController _scanLineController;
  late AnimationController _pathController;
  late AnimationController _pulseController;

  final List<String> _logs = [
    "Target locked. Image acquired.",
    "Extracting top-layer palmar topography...",
    "Analyzing Logic (理) intersections...",
    "Measuring Emotion (情) depth...",
    "Identifying Prime Gear mechanism...",
    "Calculating Physical & Spirit capacity...",
    "Compiling Karakuri Vitality Index...",
  ];

  @override
  void initState() {
    super.initState();
    _currentPattern = palmPatterns[0];
    _gearType = gearTypes[0];
    _loadHistory();

    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _pathController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _clearAllTimers();
    _cameraController?.dispose();
    _scanLineController.dispose();
    _pathController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('karakuri_vitality_history_v4');
    if (saved != null) {
      try {
        final List<dynamic> decoded = jsonDecode(saved);
        setState(() {
          _historyData = List<Map<String, dynamic>>.from(decoded);
        });
      } catch (e) {
        debugPrint('History load error');
      }
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'karakuri_vitality_history_v4',
      jsonEncode(_historyData),
    );
  }

  void _clearAllTimers() {
    _scanLogTimer?.cancel();
    _scanTimeoutTimer?.cancel();
    _autoFocusTimer?.cancel();
  }

  Future<void> _startCamera([int? cameraIndex]) async {
    setState(() {
      _step = 'camera';
      _cameraError = '';
      _isScanning = false;
      _capturedImageBytes = null;
      _focusLevel = 0.0;
    });
    _clearAllTimers();

    if (cameras.isEmpty) {
      setState(() => _cameraError = 'カメラが検出されませんでした。画面タップでシミュレーションを実行します。');
      _startAutoFocusLogic();
      return;
    }

    if (cameraIndex != null) _selectedCameraIdx = cameraIndex;

    final camera = cameras[_selectedCameraIdx];
    _cameraController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() {});
      _startAutoFocusLogic();
    } catch (e) {
      setState(() => _cameraError = 'カメラへのアクセスが拒否されたか、利用できません。');
      _startAutoFocusLogic(); // エラー時も擬似的に動作させる
    }
  }

  void _toggleCamera() {
    if (cameras.length > 1) {
      _selectedCameraIdx = (_selectedCameraIdx + 1) % cameras.length;
      _startCamera(_selectedCameraIdx);
    }
  }

  void _startAutoFocusLogic() {
    _autoFocusTimer?.cancel();
    _autoFocusTimer = Timer.periodic(const Duration(milliseconds: 250), (
      timer,
    ) {
      if (_focusLevel >= 100) {
        timer.cancel();
        Future.delayed(const Duration(milliseconds: 300), _handleCapture);
      } else {
        setState(() {
          _focusLevel += Random().nextDouble() * 8;
          if (_focusLevel > 100) _focusLevel = 100;
        });
      }
    });
  }

  Future<void> _handleCapture() async {
    if (_isScanning) return;
    _clearAllTimers();
    setState(() => _focusLevel = 100.0);

    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        final XFile file = await _cameraController!.takePicture();
        final bytes = await file.readAsBytes();
        setState(() => _capturedImageBytes = bytes);
      } catch (e) {
        debugPrint('Capture error: $e');
      }
    }

    setState(() {
      _isScanning = true;
      _scanProgress = 0;
      _currentPattern = palmPatterns[Random().nextInt(palmPatterns.length)];
    });

    _scanLineController.repeat(reverse: true);
    _pathController.forward(from: 0.0);

    int logIndex = 0;
    _scanLogTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      setState(() {
        _scanLog = _logs[logIndex];
        _scanProgress = (((logIndex + 1) / _logs.length) * 100).toInt();
      });
      logIndex++;
      if (logIndex >= _logs.length) timer.cancel();
    });

    _scanTimeoutTimer = Timer(const Duration(seconds: 5), () {
      _scanLineController.stop();
      _generateResults();
    });
  }

  void _generateResults() {
    final random = Random();
    final rLogic = random.nextInt(52) + 40;
    final rEmotion = random.nextInt(52) + 40;
    final rPhysical = random.nextInt(52) + 30;
    final rSpirit = random.nextInt(52) + 40;
    final rLuck = random.nextInt(72) + 20;

    final vTotal =
        ((rLogic + rEmotion + rPhysical * 1.5 + rSpirit + rLuck) / 5.5).floor();

    String msg = '';
    String adv = '';
    if (vTotal >= 80) {
      msg = '生命力は充満しています。全ての歯車が噛み合い、滑らかな駆動音を響かせています。';
      adv = '【指南】未知の仕掛けに挑むべし。本日は大胆な決断も吉と出ます。';
    } else if (vTotal >= 55) {
      msg = '安定した状態です。からくりは静かに、しかし確実に回っています。';
      adv = '【指南】日常の歯車を乱さず回すべし。淡々と業務をこなすのに適した一日です。';
    } else {
      msg = 'バッテリーが低下気味です。生命線にわずかな乱れ、歯車の軋みが見えます。';
      adv = '【指南】ぜんまい巻き直しの時。一切の交信を断ち、早急に目を閉じて休むべし。';
    }

    GearType gType = gearTypes[1];
    if (rLogic > 80)
      gType = gearTypes[3];
    else if (rEmotion > 80)
      gType = gearTypes[0];
    else if (rSpirit > 80)
      gType = gearTypes[2];

    final rData = [rLogic, rEmotion, rPhysical, rSpirit, rLuck];

    final newRecord = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'date':
          '${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().day.toString().padLeft(2, '0')} ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
      'score': vTotal,
      'radar': rData,
    };

    setState(() {
      _radarData = rData;
      _vitality = vTotal;
      _message = msg;
      _advice = adv;
      _gearType = gType;
      _historyData.insert(0, newRecord);
      if (_historyData.length > 30) _historyData = _historyData.sublist(0, 30);
      _isScanning = false;
      _step = 'result';
    });

    _saveHistory();
  }

  void _resetApp() {
    _clearAllTimers();
    setState(() {
      _isScanning = false;
      _focusLevel = 0.0;
      _step = 'intro';
    });
  }

  // --- UI Builders ---

  Widget _buildIntro() {
    return Stack(
      children: [
        // Background noise/pattern
        CustomPaint(painter: GridPatternPainter(), size: Size.infinite),

        Positioned(
          top: 40,
          right: 20,
          child: IconButton(
            icon: const Icon(Icons.show_chart, color: Tokens.washi2, size: 28),
            onPressed: () => setState(() => _step = 'history'),
          ),
        ),

        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    RotationTransition(
                      turns: _pulseController,
                      child: const Icon(
                        Icons.settings,
                        size: 64,
                        color: Tokens.kin,
                      ),
                    ),
                    RotationTransition(
                      turns: ReverseAnimation(_pulseController),
                      child: const Icon(
                        Icons.settings,
                        size: 32,
                        color: Tokens.kin2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'からくり生命計',
                style: TextStyle(
                  color: Tokens.kin,
                  fontSize: 12,
                  letterSpacing: 5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 48,
                    color: Tokens.washi,
                    fontWeight: FontWeight.w300,
                  ),
                  children: [
                    TextSpan(text: 'Vitality '),
                    TextSpan(
                      text: 'Lens',
                      style: TextStyle(
                        color: Tokens.kin2,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  '掌を撮影し、5つの要素と駆動器から本日のエネルギー残量を測る仕掛けです。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Tokens.washi2,
                    fontSize: 14,
                    height: 1.8,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 48),
              OutlinedButton.icon(
                onPressed: _startCamera,
                icon: const Icon(Icons.camera_alt, color: Tokens.sumi),
                label: const Text(
                  '撮影を開始',
                  style: TextStyle(
                    color: Tokens.sumi,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Tokens.kin,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  side: const BorderSide(color: Tokens.kin2),
                  elevation: 8,
                  shadowColor: Tokens.kin.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCamera() {
    return GestureDetector(
      onTap: _handleCapture,
      child: Container(
        color: Colors.black,
        width: double.infinity,
        height: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Camera Preview
            if (!_isScanning &&
                _cameraController != null &&
                _cameraController!.value.isInitialized)
              Transform.scale(
                scale: 1.0, // アスペクト比調整用（今回は簡易表示）
                child: Center(child: CameraPreview(_cameraController!)),
              ),

            // Captured Image during scan
            if (_isScanning && _capturedImageBytes != null)
              ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  0.393,
                  0.769,
                  0.189,
                  0.0,
                  0.0,
                  0.349,
                  0.686,
                  0.168,
                  0.0,
                  0.0,
                  0.272,
                  0.534,
                  0.131,
                  0.0,
                  0.0,
                  0.0,
                  0.0,
                  0.0,
                  1.0,
                  0.0,
                ]), // Sepia tone
                child: Image.memory(_capturedImageBytes!, fit: BoxFit.cover),
              ),

            // Top Bar
            Positioned(
              top: 40,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: _resetApp,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                    ),
                  ),
                  if (!_isScanning && cameras.length > 1)
                    IconButton(
                      icon: const Icon(
                        Icons.flip_camera_ios,
                        color: Colors.white,
                      ),
                      onPressed: _toggleCamera,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                      ),
                    ),
                ],
              ),
            ),

            if (_cameraError.isNotEmpty && !_isScanning)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  color: Tokens.sumi2,
                  child: Text(
                    _cameraError,
                    style: const TextStyle(color: Tokens.beni),
                  ),
                ),
              ),

            // Focus UI (Not Scanning)
            if (!_isScanning) ...[
              const Positioned(
                top: 120,
                left: 0,
                right: 0,
                child: Text(
                  '手のひらを枠内で静止させるか、\n画面をタップしてください',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Tokens.kin,
                    fontSize: 13,
                    letterSpacing: 4,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                  ),
                ),
              ),
              Center(
                child: Transform.scale(
                  scale: 1.0 - (_focusLevel * 0.001),
                  child: Container(
                    width: 260,
                    height: 320,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _focusLevel > 80
                            ? Tokens.kin2
                            : Tokens.kin.withOpacity(0.4 + (_focusLevel / 200)),
                        width: 2,
                        style: BorderStyle.solid,
                      ),
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: Stack(
                      children: [
                        if (_focusLevel > 20)
                          Center(
                            child: Text(
                              _focusLevel > 90 ? 'LOCKED' : 'TARGETING...',
                              style: const TextStyle(
                                color: Tokens.kin2,
                                fontSize: 12,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 120,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _focusLevel / 100,
                      child: Container(color: Tokens.kin),
                    ),
                  ),
                ),
              ),
            ],

            // Scanning UI
            if (_isScanning) ...[
              // SVG Lines Animation
              Center(
                child: SizedBox(
                  width: 200,
                  height: 250,
                  child: CustomPaint(
                    painter: PalmPathPainter(
                      _currentPattern,
                      _pathController.value,
                    ),
                  ),
                ),
              ),

              // Scanning Line
              AnimatedBuilder(
                animation: _scanLineController,
                builder: (context, child) {
                  return Positioned(
                    top:
                        MediaQuery.of(context).size.height *
                        _scanLineController.value,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 3,
                      decoration: const BoxDecoration(
                        color: Tokens.kin2,
                        boxShadow: [
                          BoxShadow(
                            color: Tokens.kin,
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              Positioned(
                bottom: 120,
                left: 0,
                right: 0,
                child: Text(
                  '$_scanProgress%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 40,
                    color: Tokens.kin2,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),

              Positioned(
                bottom: 40,
                left: 24,
                right: 24,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    border: Border.all(color: Tokens.border2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.terminal, color: Tokens.kin2, size: 14),
                          SizedBox(width: 8),
                          Text(
                            'KARAKURI_STATIC_ANALYSIS',
                            style: TextStyle(
                              color: Tokens.kin2,
                              fontSize: 10,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _scanLog,
                        style: const TextStyle(
                          color: Tokens.washi,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    return Stack(
      children: [
        if (_capturedImageBytes != null)
          Opacity(
            opacity: 0.05,
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Colors.grey,
                BlendMode.saturation,
              ),
              child: Image.memory(
                _capturedImageBytes!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),

        Center(
          child: SingleChildScrollView(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Tokens.sumi2,
                border: Border.all(color: Tokens.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'SOCIAL BATTERY',
                    style: TextStyle(
                      color: Tokens.kin,
                      fontSize: 12,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$_vitality',
                        style: TextStyle(
                          fontSize: 80,
                          height: 1.0,
                          color: _vitality >= 55 ? Tokens.kin2 : Tokens.beni,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12.0),
                        child: Text(
                          '%',
                          style: TextStyle(fontSize: 32, color: Tokens.kin),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 120,
                          child: CustomPaint(
                            painter: KarakuriRadarPainter(_radarData),
                          ),
                        ),
                      ),
                      Container(width: 1, height: 100, color: Tokens.border2),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '主要駆動器',
                                style: TextStyle(
                                  color: Tokens.gin,
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _gearType.name.split(' ')[0],
                                style: const TextStyle(
                                  color: Tokens.kin2,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _gearType.desc,
                                style: const TextStyle(
                                  color: Tokens.washi3,
                                  fontSize: 11,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),
                  Text(
                    _message,
                    style: const TextStyle(
                      color: Tokens.washi,
                      fontSize: 14,
                      height: 1.8,
                    ),
                    textAlign: TextAlign.justify,
                  ),

                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0x0DC9A84C),
                      border: Border(
                        left: BorderSide(color: Tokens.kin, width: 2),
                      ),
                    ),
                    child: Text(
                      _advice,
                      style: const TextStyle(
                        color: Tokens.kin2,
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: _showCertificatePreview,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text(
                      '証明符を発行 (プレビュー)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Tokens.kin,
                      foregroundColor: Tokens.sumi,
                      minimumSize: const Size(double.infinity, 56),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _resetApp,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text(
                      'もう一度測る',
                      style: TextStyle(letterSpacing: 2),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Tokens.kin,
                      side: const BorderSide(color: Tokens.border2),
                      minimumSize: const Size(double.infinity, 56),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistory() {
    return Scaffold(
      backgroundColor: Tokens.sumi,
      appBar: AppBar(
        backgroundColor: Tokens.sumi2,
        title: const Text(
          '測定履歴',
          style: TextStyle(color: Tokens.kin2, fontSize: 16, letterSpacing: 2),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Tokens.washi),
          onPressed: () => setState(() => _step = 'intro'),
        ),
      ),
      body: _historyData.isEmpty
          ? const Center(
              child: Text('記録がありません', style: TextStyle(color: Tokens.gin)),
            )
          : Column(
              children: [
                if (_historyData.length >= 2)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Tokens.border),
                      color: Colors.black38,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'バイオリズム推移',
                          style: TextStyle(
                            color: Tokens.washi2,
                            fontSize: 12,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 100,
                          width: double.infinity,
                          child: CustomPaint(
                            painter: HistoryGraphPainter(_historyData),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _historyData.length,
                    itemBuilder: (context, index) {
                      final item = _historyData[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Tokens.sumi3,
                          child: Text(
                            '${item['score']}',
                            style: TextStyle(
                              color: item['score'] >= 55
                                  ? Tokens.kin2
                                  : Tokens.beni,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          item['date'],
                          style: const TextStyle(color: Tokens.washi),
                        ),
                        subtitle: Text(
                          '理:${item['radar'][0]} 情:${item['radar'][1]} 魄:${item['radar'][2]}',
                          style: const TextStyle(
                            color: Tokens.gin,
                            fontSize: 10,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  // Canvas合成と画像プレビュー
  Future<void> _showCertificatePreview() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, 1080, 1080));

    // 背景
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1080, 1080),
      Paint()..color = Tokens.sumi,
    );

    // カメラ画像の合成
    if (_capturedImageBytes != null) {
      try {
        final codec = await ui.instantiateImageCodec(_capturedImageBytes!);
        final frameInfo = await codec.getNextFrame();
        final image = frameInfo.image;

        final paint = Paint()..color = Colors.white.withOpacity(0.35);
        final scale = max(1080 / image.width, 1080 / image.height);
        final w = image.width * scale;
        final h = image.height * scale;
        final dx = (1080 - w) / 2;
        final dy = (1080 - h) / 2;

        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Rect.fromLTWH(dx, dy, w, h),
          paint,
        );
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 1080, 1080),
          Paint()..color = const Color(0x660A0906),
        ); // 暗くする
      } catch (e) {
        debugPrint('Image overlay failed');
      }
    }

    // パス描画
    canvas.save();
    canvas.translate(1080 / 2 - 250, 200);
    canvas.scale(2.5, 2.5);
    final shadowPaint = Paint()
      ..color = Tokens.kin2.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawPath(_currentPattern.heart, shadowPaint);
    canvas.drawPath(
      _currentPattern.heart,
      Paint()
        ..color = Tokens.kin2
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawPath(
      _currentPattern.head,
      Paint()
        ..color = Tokens.washi
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawPath(
      _currentPattern.life,
      Paint()
        ..color = Tokens.kin
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    canvas.restore();

    // 枠
    canvas.drawRect(
      const Rect.fromLTWH(50, 50, 980, 980),
      Paint()
        ..color = Tokens.kin
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    // 文字描画用ヘルパー
    void drawText(
      String text,
      double x,
      double y,
      double size,
      Color color, {
      bool isBold = false,
    }) {
      final paragraphStyle = ui.ParagraphStyle(
        textAlign: TextAlign.center,
        fontSize: size,
        fontWeight: isBold ? FontWeight.bold : FontWeight.w300,
      );
      final builder = ui.ParagraphBuilder(paragraphStyle)
        ..pushStyle(ui.TextStyle(color: color))
        ..addText(text);
      final paragraph = builder.build()
        ..layout(const ui.ParagraphConstraints(width: 1080));
      canvas.drawParagraph(paragraph, Offset(0, y));
    }

    drawText('Vitality Lens', 0, 100, 40, Tokens.washi);
    drawText('からくり生命計 測定証明符', 0, 160, 24, Tokens.kin, isBold: true);

    drawText(
      '$_vitality %',
      0,
      750,
      180,
      _vitality >= 55 ? Tokens.kin2 : Tokens.beni,
    );
    drawText('Social Battery', 0, 700, 24, Tokens.washi2);
    drawText('主要駆動器：${_gearType.name}', 0, 940, 26, Tokens.kin, isBold: true);
    drawText(
      'DATE: ${DateTime.now().toString().split(' ')[0]} | KARAKURI STUDIO',
      0,
      980,
      16,
      Tokens.gin,
    );

    // 画像化
    final picture = recorder.endRecording();
    final img = await picture.toImage(1080, 1080);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tokens.sumi3,
        title: const Text(
          '証明符プレビュー',
          style: TextStyle(color: Tokens.kin2, fontSize: 16),
        ),
        content: Image.memory(pngBytes, fit: BoxFit.contain),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる', style: TextStyle(color: Tokens.washi)),
          ),
          // ※実機に保存する場合は image_gallery_saver プラグイン等を使用して保存ロジックを追加します
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Tokens.kin,
              foregroundColor: Tokens.sumi,
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case 'intro':
        return _buildIntro();
      case 'camera':
        return _buildCamera();
      case 'result':
        return _buildResult();
      case 'history':
        return _buildHistory();
      default:
        return const SizedBox();
    }
  }
}

// --- Custom Painters ---

// レーダーチャート描画
class KarakuriRadarPainter extends CustomPainter {
  final List<int> data;
  KarakuriRadarPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = min(cx, cy) - 20;

    final bgPaint = Paint()
      ..color = Tokens.border2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final dashPaint = Paint()
      ..color = Tokens.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // 背景グリッド (25, 50, 75, 100)
    for (var pct in [0.25, 0.5, 0.75, 1.0]) {
      final path = Path();
      for (var i = 0; i < 5; i++) {
        final angle = (pi * 2 * i) / 5 - pi / 2;
        final dist = r * pct;
        final x = cx + dist * cos(angle);
        final y = cy + dist * sin(angle);
        if (i == 0)
          path.moveTo(x, y);
        else
          path.lineTo(x, y);
      }
      path.close();
      canvas.drawPath(path, pct == 1.0 ? bgPaint : dashPaint);
    }

    // データポリゴン
    final dataPath = Path();
    for (var i = 0; i < 5; i++) {
      final angle = (pi * 2 * i) / 5 - pi / 2;
      final dist = r * (data[i] / 100.0);
      final x = cx + dist * cos(angle);
      final y = cy + dist * sin(angle);
      if (i == 0)
        dataPath.moveTo(x, y);
      else
        dataPath.lineTo(x, y);
    }
    dataPath.close();

    canvas.drawPath(
      dataPath,
      Paint()
        ..color = Tokens.kin.withOpacity(0.25)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      dataPath,
      Paint()
        ..color = Tokens.kin
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // データ点とラベル
    final labels = ['理', '情', '魄', '魂', '運'];
    for (var i = 0; i < 5; i++) {
      final angle = (pi * 2 * i) / 5 - pi / 2;
      // 点
      final dist = r * (data[i] / 100.0);
      canvas.drawCircle(
        Offset(cx + dist * cos(angle), cy + dist * sin(angle)),
        3,
        Paint()..color = Tokens.kin2,
      );

      // ラベル
      final textDist = r + 15;
      final tx = cx + textDist * cos(angle);
      final ty = cy + textDist * sin(angle);
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: const TextStyle(color: Tokens.washi2, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(tx - tp.width / 2, ty - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// 履歴グラフ描画
class HistoryGraphPainter extends CustomPainter {
  final List<Map<String, dynamic>> history;
  HistoryGraphPainter(this.history);

  @override
  void paint(Canvas canvas, Size size) {
    if (history.length < 2) return;
    final data = history.take(10).toList().reversed.toList(); // 最大10件を古い順に
    final w = size.width;
    final h = size.height;

    final gridPaint = Paint()
      ..color = Tokens.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h), Offset(w, h), gridPaint);
    canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), gridPaint);
    canvas.drawLine(Offset(0, 0), Offset(w, 0), gridPaint);

    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final score = data[i]['score'] as int;
      final x = (i / max(1, data.length - 1)) * w;
      final y = h - ((score - 20) / 80).clamp(0.0, 1.0) * h;
      if (i == 0)
        path.moveTo(x, y);
      else
        path.lineTo(x, y);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = Tokens.kin
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    for (var i = 0; i < data.length; i++) {
      final score = data[i]['score'] as int;
      final x = (i / max(1, data.length - 1)) * w;
      final y = h - ((score - 20) / 80).clamp(0.0, 1.0) * h;
      canvas.drawCircle(Offset(x, y), 3, Paint()..color = Tokens.kin2);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// スキャン時の手相パスアニメーション描画
class PalmPathPainter extends CustomPainter {
  final PalmPattern pattern;
  final double progress;
  PalmPathPainter(this.pattern, this.progress);

  void _drawAnimatedPath(
    Canvas canvas,
    Path path,
    Paint paint,
    double delay,
    double duration,
  ) {
    double p = ((progress - delay) / duration).clamp(0.0, 1.0);
    if (p <= 0) return;
    for (var metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0.0, metric.length * p), paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate((size.width - 200) / 2, (size.height - 250) / 2); // 中央寄せ調整

    final heartPaint = Paint()
      ..color = Tokens.kin2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4);
    final headPaint = Paint()
      ..color = Tokens.washi
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final lifePaint = Paint()
      ..color = Tokens.kin
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    _drawAnimatedPath(canvas, pattern.heart, heartPaint, 0.0, 0.4);
    _drawAnimatedPath(canvas, pattern.head, headPaint, 0.3, 0.4);
    _drawAnimatedPath(canvas, pattern.life, lifePaint, 0.6, 0.4);
  }

  @override
  bool shouldRepaint(covariant PalmPathPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// イントロの背景グリッド描画
class GridPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Tokens.kin.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
