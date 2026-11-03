#include <ArduinoBLE.h>

// Déclaration du service BLE et des caractéristiques
BLEService radarService("180C"); // UUID du service
BLECharacteristic distanceChar("2A56", BLERead | BLENotify, sizeof(int32_t)); // Caractéristique distance (int32_t)

// Pin du capteur de distance (capteur analogique sur A7)
const int proximityPin = A7;

void setup() {
  // Initialisation du port série
  Serial.begin(9600);
  while (!Serial); // Attendre l'initialisation du moniteur série

  Serial.println("Initialisation...");

  // Initialisation du module BLE
  if (!BLE.begin()) {
    Serial.println("Erreur : impossible de démarrer le module BLE !");
    while (1);
  }
  Serial.println("Module BLE démarré avec succès.");

  // Configuration des services et caractéristiques BLE
  BLE.setLocalName("Radar_maes_emrys");    // À personnaliser avec votre Nom et Prénom !
  BLE.setAdvertisedService(radarService);  // Associer le service
  radarService.addCharacteristic(distanceChar); // Ajouter la caractéristique au service
  BLE.addService(radarService);            // Ajouter le service BLE
  BLE.advertise();                         // Commencer à faire de la publicité BLE

  Serial.println("En attente de connexion...");
}

void loop() {
  // Vérifier si un périphérique central (smartphone) est connecté
  BLEDevice central = BLE.central();

  if (central) {
    Serial.print("Connecté à : ");
    Serial.println(central.address());

    while (central.connected()) {
      // Lire la valeur brute du capteur
      int proximityValue = analogRead(proximityPin);
      // Convertir la valeur brute en distance (ajustez la plage selon votre capteur)
      int distance = map(proximityValue, 100, 500, 100, 0); // Ajustez si nécessaire
      distance = constrain(distance, 0, 100); // Limiter entre 0 et 100 cm

      // Afficher les informations sur le moniteur série
      Serial.print("Valeur brute du capteur : ");
      Serial.print(proximityValue);
      Serial.print(" | Distance estimée : ");
      Serial.print(distance);
      Serial.println(" cm");

      // Envoyer la distance directement en tant qu'int32_t
      distanceChar.writeValue((int32_t)distance);

      // Délai pour éviter les mises à jour trop fréquentes
      delay(200);
    }

    // Si déconnecté
    Serial.print("Déconnecté de : ");
    Serial.println(central.address());
  }
}
