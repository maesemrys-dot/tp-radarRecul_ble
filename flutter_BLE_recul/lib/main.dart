import 'dart:async'; // Pour utiliser Timer
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart'; // Pour jouer le bip sonore
import 'package:ble_radar_recul/services/ble_service.dart';


/// Point d'entrée principal de l'application Flutter.
void main() {
  runApp(const MyApp());
}

/// Widget racine de l'application (StatelessWidget).
/// Configure le thème global (Material 3) et définit la page d'accueil.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Radar de Recul BLE',
      // Configuration du thème de l'application
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      // Page d'accueil avec le titre de la vue
      home: const RadarPage(title: 'Radar de Recul'),
    );
  }
}

/// Page principale du radar de recul (StatefulWidget).
/// Gère l'affichage dynamique des données reçues du capteur.
class RadarPage extends StatefulWidget {
  const RadarPage({super.key, required this.title});
  final String title;

  @override
  State<RadarPage> createState() => _RadarPageState();
}

/// État associé à la page RadarPage.
/// Écoute le service BLE et met à jour l'interface utilisateur.
class _RadarPageState extends State<RadarPage> {
  // Instance du service BLE (Singleton)
  final BleService _bleService = BleService();

  // Distance mesurée en centimètres (-1 indique aucune donnée / déconnecté)
  int _distance = -1;
 // --- Nouveaux attributs pour l'alerte sonore ---
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _beepTimer;
  int _currentIntervalMs = 0; // Mémorise la cadence actuelle du Timer

  @override
  void initState() {
    super.initState();
    // Initialisation et démarrage de la recherche BLE au chargement du widget
    _initBleService();
  }

  /// Vérifie les permissions nécessaires et initialise l'écoute des données BLE.
  Future<void> _initBleService() async {
    // Si toutes les autorisations sont accordées, on lance le scan
    if (await _bleService.checkPermissions()) {
      _bleService.startScan();
    }

    // Écoute en temps réel des changements de distance émis par le flux (stream)
    _bleService.distanceStream.listen((distance) {
      setState(() {
        _distance = distance;
      });
      // Mise à jour de la cadence du bip à chaque nouvelle mesure
      _updateBeepAlert();

    });
  }

  /// Détermine la couleur d'alerte en fonction de la distance mesurée :
  /// - Gris : aucune valeur valide / déconnecté (< 0)
  /// - Rouge : danger imminent (< 30 cm)
  /// - Orange : attention / proximité (< 60 cm)
  /// - Vert clair : zone intermédiaire (< 90 cm)
  /// - Vert : zone sécurisée (>= 90 cm)
  Color _getDistanceColor() {
    if (_distance < 0) return Colors.grey;
    // A compléter
    if (_distance < 90) return Colors.lightGreen;
    return Colors.green;
  }

  /// Retourne l'intervalle entre deux bips (en ms) selon la distance,
  /// ou 0 si aucun bip ne doit être émis.
  int _getBeepIntervalMs() {
    if (_distance < 0 || _distance >= 90) return 0; // Silencieux (déconnecté ou zone sûre)
    if (_distance < 30) return 550;                 // Danger imminent (Rouge : bip très rapide)
    if (_distance < 60) return 650;                 // Attention (Orange : bip moyen)
    return 800;                                     // Zone intermédiaire (Vert clair : bip lent)
  }

  /// Ajuste le Timer de bip uniquement lorsque la zone de proximité change.
  void _updateBeepAlert() {
    final int newIntervalMs = _getBeepIntervalMs();
    // Si on est déjà sur la bonne cadence, on ne touche pas au Timer en cours
    if (newIntervalMs == _currentIntervalMs) return;

    _currentIntervalMs = newIntervalMs;
    _beepTimer?.cancel();

    // Si la cadence est > 0 (zones vert clair, orange ou rouge), on lance le Timer
    if (_currentIntervalMs > 0) {
      _playBeep(); // Premier bip immédiat au changement de zone
      _beepTimer = Timer.periodic(
        Duration(milliseconds: _currentIntervalMs),
        (_) => _playBeep(),
      );
    }
  }

  /// Joue le son court du radar.
  Future<void> _playBeep() async {
    await _audioPlayer.stop(); // Coupe le bip précédent s'il n'est pas fini
    await _audioPlayer.play(AssetSource('sounds/bip.mp3'));
  }

  @override
  void dispose() {
    // Libération propre des ressources et abonnements du service BLE
    _bleService.dispose();
    _audioPlayer.dispose();
    _bleService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Barre supérieure de l'application
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      // Corps principal centré
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // --- Section 1 : Indicateur d'état de la connexion Bluetooth ---
            StreamBuilder<bool>(
              stream: _bleService.connectionState,
              initialData: false,
              builder: (context, snapshot) {
                final isConnected = snapshot.data ?? false;
                return Column(
                  children: [
                    // Icône d'état Bluetooth (bleue si connecté, grise sinon)
                    Icon(
                      isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                      size: 50,
                      color: isConnected ? Colors.blue : Colors.grey,
                    ),
                    const SizedBox(height: 20),
                    // Libellé textuel de connexion
                    Text(
                      isConnected ? 'Connecté' : 'Non connecté',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 40),

            // --- Section 2 : Affichage du radar (si connecté) ou bouton de scan ---
            StreamBuilder<bool>(
              stream: _bleService.connectionState,
              initialData: false,
              builder: (context, snapshot) {
                final isConnected = snapshot.data ?? false;
                if (isConnected) {
                  // Cercle visuel du radar avec couleur dynamique selon la distance
                  return Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _getDistanceColor(),
                    ),
                    child: Center(
                      // Affichage de la distance en centimètres au centre du cercle
                      child: Text(
                        _distance >= 0 ? '$_distance cm' : '---',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                            ),
                      ),
                    ),
                  );
                } else {
                  // Bouton permettant de relancer manuellement le scan BLE si déconnecté
                  return ElevatedButton(
                    onPressed: _bleService.isScanning ? null : _bleService.startScan,
                    child: Text(_bleService.isScanning ? 'Recherche...' : 'Rechercher'),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
