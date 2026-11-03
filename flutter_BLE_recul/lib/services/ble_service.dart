import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service gérant l'ensemble de la communication Bluetooth Low Energy (BLE) :
/// - Vérification et demande des permissions
/// - Scan et filtrage des périphériques à proximité
/// - Connexion à l'Arduino / ESP32 du radar de recul
/// - Réception et décodage en temps réel des mesures de distance
class BleService {
  // Implémentation du pattern Singleton pour garantir une unique instance du service
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  // Périphérique Bluetooth connecté
  BluetoothDevice? _device;
  // Indicateur d'état de la connexion
  bool _isConnected = false;
  // Abonnement aux changements d'état de connexion de l'appareil
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  // Minuteur de sécurité pour limiter la durée de recherche BLE
  Timer? _scanTimer;
  // Indicateur indiquant si un scan est actuellement en cours
  bool _isScanning = false;

  // Identifiants GATT (Service et Caractéristique) configurés sur le microcontrôleur
  final String serviceUuid = "180C";
  final String characteristicUuid = "2A56";
  // Adresse MAC cible de l'appareil Arduino / ESP32
  final String deviceMacAddress = "2d:69:64:e1:18:29";

  // Streams (flux) pour communiquer l'état de connexion et les mesures aux widgets Flutter
  final _connectionStateController = StreamController<bool>.broadcast();
  final _distanceController = StreamController<int>.broadcast();

  // Getters publics exposant les flux et les états
  Stream<bool> get connectionState => _connectionStateController.stream;
  Stream<int> get distanceStream => _distanceController.stream;
  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;

  /// Vérifie et demande les permissions requises à l'utilisateur :
  /// - Bluetooth standard
  /// - Scan Bluetooth (Android 12+)
  /// - Connexion Bluetooth (Android 12+)
  /// - Localisation (nécessaire pour le scan BLE sous Android)
  Future<bool> checkPermissions() async {
    return await Permission.bluetooth.request().isGranted &&
        await Permission.bluetoothScan.request().isGranted &&
        await Permission.bluetoothConnect.request().isGranted &&
        await Permission.location.request().isGranted;
  }

  /// Démarre la recherche (scan) des périphériques BLE à proximité.
  Future<void> startScan() async {
    // Évite de lancer plusieurs scans simultanés
    if (_isScanning) return;
    
    _isScanning = true;
    
    try {
      // Vérification de la disponibilité du matériel Bluetooth
      if (await FlutterBluePlus.isAvailable == false) {
        print('Bluetooth n\'est pas disponible sur cet appareil');
        return;
      }

      // Activation automatique du Bluetooth s'il est éteint
      if (await FlutterBluePlus.adapterState.first == BluetoothAdapterState.off) {
        await FlutterBluePlus.turnOn();
      }

      print('Démarrage du scan BLE...');
      // Lance le scan pendant 10 secondes maximum
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      // Écoute les résultats de recherche au fur et à mesure
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult result in results) {
          print('Appareil trouvé: ${result.device.localName} - ${result.device.remoteId}');
          // Vérifie si l'adresse MAC correspond à celle du radar
          if (result.device.remoteId.toString().toLowerCase() == deviceMacAddress.toLowerCase()) {
            print('Arduino trouvé! Tentative de connexion...');
            FlutterBluePlus.stopScan();
            _connectToDevice(result.device);
            break;
          }
        }
      });

      // Minuteur pour réinitialiser le flag de scan après le timeout de 10 secondes
      _scanTimer = Timer(const Duration(seconds: 10), () {
        FlutterBluePlus.stopScan();
        _isScanning = false;
      });
    } catch (e) {
      print('Erreur pendant le scan: $e');
      _isScanning = false;
    }
  }

  /// Établit la connexion avec le périphérique Bluetooth et souscrit aux notifications de distance.
  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      print('Tentative de connexion à ${device.localName}...');
      await device.connect(timeout: const Duration(seconds: 15));
      print('Connecté au périphérique');
      
      _device = device;
      _isConnected = true;
      _connectionStateController.add(true);

      // Surveillance continue de la connexion (déconnexion inopinée, etc.)
      _connectionSubscription = device.connectionState.listen((state) {
        print('État de la connexion: $state');
        _isConnected = state == BluetoothConnectionState.connected;
        _connectionStateController.add(_isConnected);
        // Si déconnecté, réinitialisation de la distance à -1
        if (!_isConnected) {
          _distanceController.add(-1);
        }
      });

      // Découverte des services GATT exposés par l'Arduino
      print('Découverte des services...');
      List<BluetoothService> services = await device.discoverServices();
      print('Services trouvés: ${services.length}');
      
      for (var service in services) {
        print('Service trouvé: ${service.uuid.toString()}');
        // Recherche du service contenant notre UUID
        if (service.uuid.toString().toUpperCase().contains(serviceUuid)) {
          var characteristics = service.characteristics;
          for (var characteristic in characteristics) {
            print('Caractéristique trouvée: ${characteristic.uuid.toString()}');
            // Recherche de la caractéristique de mesure de distance
            if (characteristic.uuid.toString().toUpperCase().contains(characteristicUuid)) {
              print('Configuration des notifications...');
              // Activation des notifications pour recevoir les données en temps réel
              await characteristic.setNotifyValue(true);
              characteristic.onValueReceived.listen((value) {
                if (value.isNotEmpty) {
                  int distance = 0;
                  // Si la valeur reçue fait au moins 4 octets, décodage en entier 32-bit (Little Endian)
                  if (value.length >= 4) {
                    ByteData byteData = ByteData.sublistView(Uint8List.fromList(value));
                    distance = byteData.getInt32(0, Endian.little);
                  } else {
                    // Sinon, lecture du premier octet
                    distance = value[0];
                  }
                  print('Distance reçue: $distance');
                  // Émission de la nouvelle distance vers les abonnés du stream
                  _distanceController.add(distance);
                }
              });
            }
          }
        }
      }
    } catch (e) {
      print('Erreur de connexion: $e');
      _isConnected = false;
      _connectionStateController.add(false);
    }
  }

  /// Déconnecte manuellement le périphérique et annule les abonnements.
  Future<void> disconnect() async {
    await _device?.disconnect();
    _connectionSubscription?.cancel();
    _scanTimer?.cancel();
    _isConnected = false;
    _connectionStateController.add(false);
  }

  /// Libère toutes les ressources (fermeture des Streams et déconnexion).
  void dispose() {
    _connectionStateController.close();
    _distanceController.close();
    disconnect();
  }
}